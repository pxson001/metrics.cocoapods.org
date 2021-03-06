require 'sinatra/base'
require 'app/models'

ENV['INCOMING_TRUNK_HOOK_PATH'] ||= 'jmango360'

class MetricsApp < Sinatra::Base
  set :protection, :except => :json_csrf

  def sanitize_metrics(metrics, debug = false)
    return unless metrics
    metrics = metrics.values.dup
    metrics.delete(:id)
    metrics.delete(:pod_id)
    metrics.delete(:not_found) unless debug
    metrics
  end

  before do
    type = content_type(:json)
  end

  def json_error(status, message)
    error(status, { 'error' => message }.to_json)
  end

  def json_message(status, content)
    halt(status, content.to_json)
  end

  get '/' do
    redirect '/api/v1/status'
  end

  get '/api/v1/status' do
    latest_pod_stats = TotalStats.last
    {
      :github => {
        :total => GithubPodMetrics.count,
        :complete => GithubPodMetrics.where('not_found = 0').count,
        :not_found => GithubPodMetrics.where('not_found > 0').count,
      },
      :cocoadocs => {
        :total => CocoadocsPodMetrics.count,
      }
      # ,
      # :cocoapods => {
      #   :all_pods_linked => latest_pod_stats.download_total,
      #   :targets_total => latest_pod_stats.projects_total,
      #   :all_apps_total => latest_pod_stats.app_total,
      #   :all_tests_total => latest_pod_stats.tests_total,
      #   :all_extensions_total => latest_pod_stats.extensions_total,
      # }
    }.to_json
  end

  ['/api/v1/pods/:name.json', '/api/v1/pods/:name'].each do |path|
    get path do
      pod = Pod.first(:name => params[:name])
      if pod
        github_metrics = pod.github_pod_metrics
        cocoadocs_metrics = pod.cocoadocs_pod_metrics
        # stats_metrics = pod.stats_metrics

        if github_metrics || cocoadocs_metrics || stats_metrics
          json_message(
            200,
            :github => sanitize_metrics(github_metrics, params[:debug]),
            :cocoadocs => sanitize_metrics(cocoadocs_metrics, params[:debug])
            # ,
            # :stats => sanitize_metrics(stats_metrics, params[:debug]),
          )
        end
      end
      json_error(404, "No pod found with the specified name: #{params[:name]}")
    end
  end

  post "/api/v1/pods/:name/reset/#{ENV['INCOMING_TRUNK_HOOK_PATH']}" do
    pod = Pod.first(:name => params[:name])
    if pod
      if Metrics::Github.new.reset_not_found(pod)
        # Also directly try to update.
        Metrics::Github.new.update(pod)
        "#{pod.name} reset."
      else
        "#{pod.name} not reset."
      end
    end
  end

  # Install trunk hook path for POST (ping from trunk).
  #
  post "/hooks/trunk/#{ENV['INCOMING_TRUNK_HOOK_PATH']}" do
    data = JSON.parse(request.body.read)
    pod = Pod.first(:name => data['pod'])
    Metrics::Updater.reset(pod) if pod

    'Metrics ok.'
  end
end

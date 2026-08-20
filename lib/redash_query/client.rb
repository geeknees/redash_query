# ABOUTME: HTTP client for Redash API — query execution, job polling, result retrieval.
# Uses stdlib net/http only. No API key is written to any log or error message.
require "net/http"
require "json"
require "uri"
require_relative "error"

module RedashQuery
  class Client
    LOCAL_HTTP_HOSTS = %w[localhost 127.0.0.1 ::1 [::1]].freeze

    def initialize(base_url:, api_key:)
      @base_url = normalize_base_url(base_url)
      raise ConfigError, "REDASH_API_KEY is empty" if api_key.to_s.empty?

      @api_key  = api_key
    end

    def run_query(query_id:, params: {}, max_age: 0, format: "json", timeout: 120, poll_interval: 1)
      body = JSON.generate({ "max_age" => max_age, "parameters" => params })
      response = post("/api/queries/#{query_id}/results", body)
      data = parse_json(response)

      query_result_id =
        if data["query_result"]
          data.dig("query_result", "id")
        elsif data["job"]
          poll_job(data.dig("job", "id"), timeout: timeout, poll_interval: poll_interval)
        else
          raise ApiError, "Unexpected response from Redash"
        end

      get_result(query_result_id, format)
    end

    def list_datasources
      response = get("/api/data_sources")
      parse_json(response)
    end

    def create_query(name:, sql:, datasource_id:, description: "")
      body = JSON.generate({
        "name"           => name,
        "query"          => sql,
        "data_source_id" => datasource_id,
        "description"    => description
      })
      response = post("/api/queries", body)
      parse_json(response)
    end

    def archive_query(query_id:)
      delete("/api/queries/#{query_id}")
      nil
    end

    def query_status(query_id:)
      response = get("/api/queries/#{query_id}")
      parse_json(response)
    end

    private

    def normalize_base_url(base_url)
      uri = URI.parse(base_url.to_s)

      unless uri.is_a?(URI::HTTP) && uri.host
        raise ConfigError, "REDASH_BASE_URL must be a valid HTTP(S) URL"
      end
      if uri.userinfo
        raise ConfigError, "REDASH_BASE_URL must not contain embedded credentials"
      end

      local_http = uri.scheme == "http" && LOCAL_HTTP_HOSTS.include?(uri.host.downcase)
      unless uri.scheme == "https" || local_http
        raise ConfigError, "REDASH_BASE_URL must use HTTPS (HTTP is allowed only for localhost)"
      end

      uri.to_s.chomp("/")
    rescue URI::InvalidURIError
      raise ConfigError, "REDASH_BASE_URL must be a valid HTTP(S) URL"
    end

    def poll_job(job_id, timeout:, poll_interval:)
      deadline = Time.now + timeout
      loop do
        response = get("/api/jobs/#{job_id}")
        data     = parse_json(response)
        job      = data["job"]
        status   = job["status"]

        case status
        when 3
          return job["query_result_id"]
        when 4, 5
          raise JobFailedError, job["error"] || "Query job failed (status #{status})"
        when 1, 2
          $stderr.puts "Polling job #{job_id}..."
        else
          $stderr.puts "Warning: unknown job status #{status}, continuing..."
        end

        sleep poll_interval
        raise TimeoutError, "Query timed out after #{timeout} seconds" if Time.now > deadline
      end
    end

    def get_result(query_result_id, format)
      ext      = format == "csv" ? "csv" : "json"
      response = get("/api/query_results/#{query_result_id}.#{ext}")
      response.body
    end

    def post(path, body)
      uri = URI("#{@base_url}#{path}")
      http_request(uri) do |http|
        req                 = Net::HTTP::Post.new(uri)
        req["Content-Type"] = "application/json"
        set_auth(req)
        req.body = body
        http.request(req)
      end
    end

    def get(path)
      uri = URI("#{@base_url}#{path}")
      http_request(uri) do |http|
        req = Net::HTTP::Get.new(uri)
        set_auth(req)
        http.request(req)
      end
    end

    def delete(path)
      uri = URI("#{@base_url}#{path}")
      http_request(uri) do |http|
        req = Net::HTTP::Delete.new(uri)
        set_auth(req)
        http.request(req)
      end
    end

    def http_request(uri, &block)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
        response = block.call(http)
        handle_response(response)
      end
    rescue SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::ECONNRESET => e
      raise ApiError, "Network error: #{e.message}"
    end

    def handle_response(response)
      case response.code.to_i
      when 200..299
        response
      when 401, 403
        raise ApiError, "Unauthorized: check your Redash API key configuration"
      when 404
        raise ApiError, "Not found: query or resource does not exist"
      when 500..599
        raise ApiError, "Server error: #{response.code}"
      else
        raise ApiError, "Unexpected HTTP status: #{response.code}"
      end
    end

    def set_auth(req)
      req["Authorization"] = "Key #{@api_key}"
    end

    def parse_json(response)
      JSON.parse(response.body)
    rescue JSON::ParserError => e
      raise ApiError, "Invalid JSON response: #{e.message}"
    end
  end
end

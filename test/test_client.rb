require_relative "test_helper"

BASE_URL        = "https://redash.example.com"
BASE_URL_SLASH  = "https://redash.example.com/"
API_KEY         = "test_api_key_abc123"

IMMEDIATE_RESULT_RESPONSE = JSON.generate({
  "query_result" => { "id" => 456 }
})

RESULT_JSON_RESPONSE = JSON.generate({
  "query_result" => {
    "data" => { "columns" => [{ "name" => "count" }], "rows" => [{ "count" => 1 }] }
  }
})

RESULT_CSV_RESPONSE = "count\n1\n"

def stub_immediate_result(base = BASE_URL)
  stub_request(:post, "#{base}/api/queries/123/results")
    .to_return(status: 200, body: IMMEDIATE_RESULT_RESPONSE, headers: { "Content-Type" => "application/json" })
end

def stub_result_json(base = BASE_URL)
  stub_request(:get, "#{base}/api/query_results/456.json")
    .to_return(status: 200, body: RESULT_JSON_RESPONSE, headers: { "Content-Type" => "application/json" })
end

def stub_result_csv(base = BASE_URL)
  stub_request(:get, "#{base}/api/query_results/456.csv")
    .to_return(status: 200, body: RESULT_CSV_RESPONSE, headers: { "Content-Type" => "text/csv" })
end

class TestClientUrlNormalization < Minitest::Test
  def test_trailing_slash_is_normalized
    stub_immediate_result(BASE_URL)
    stub_result_json(BASE_URL)
    client = RedashQuery::Client.new(base_url: BASE_URL_SLASH, api_key: API_KEY)
    result = client.run_query(query_id: 123, format: "json")
    assert_equal RESULT_JSON_RESPONSE, result
  end

  def test_no_trailing_slash_works
    stub_immediate_result(BASE_URL)
    stub_result_json(BASE_URL)
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    result = client.run_query(query_id: 123, format: "json")
    assert_equal RESULT_JSON_RESPONSE, result
  end
end

class TestClientBaseUrlValidation < Minitest::Test
  def test_remote_http_url_is_rejected
    error = assert_raises(RedashQuery::ConfigError) do
      RedashQuery::Client.new(base_url: "http://redash.example.com", api_key: API_KEY)
    end

    assert_includes error.message, "HTTPS"
  end

  def test_loopback_http_urls_are_allowed_for_development
    %w[http://localhost:5000 http://127.0.0.1:5000 http://[::1]:5000].each do |url|
      client = RedashQuery::Client.new(base_url: url, api_key: API_KEY)

      assert_instance_of RedashQuery::Client, client
    end
  end

  def test_localhost_lookalike_http_url_is_rejected
    assert_raises(RedashQuery::ConfigError) do
      RedashQuery::Client.new(base_url: "http://localhost.example.com", api_key: API_KEY)
    end
  end

  def test_invalid_url_is_rejected
    error = assert_raises(RedashQuery::ConfigError) do
      RedashQuery::Client.new(base_url: "not a URL", api_key: API_KEY)
    end

    assert_includes error.message, "REDASH_BASE_URL"
  end

  def test_url_with_embedded_credentials_is_rejected
    base_url = ["https://", "user:password", "@", "redash.example.com"].join

    error = assert_raises(RedashQuery::ConfigError) do
      RedashQuery::Client.new(base_url: base_url, api_key: API_KEY)
    end

    assert_includes error.message, "credentials"
  end

  def test_empty_api_key_is_rejected
    error = assert_raises(RedashQuery::ConfigError) do
      RedashQuery::Client.new(base_url: BASE_URL, api_key: "")
    end

    assert_includes error.message, "REDASH_API_KEY"
  end
end

JOB_RESPONSE = JSON.generate({
  "job" => { "id" => "job-abc", "status" => 1 }
})

JOB_DONE_RESPONSE = JSON.generate({
  "job" => { "id" => "job-abc", "status" => 3, "query_result_id" => 456 }
})

JOB_FAILED_RESPONSE = JSON.generate({
  "job" => { "id" => "job-abc", "status" => 4, "error" => "division by zero" }
})

JOB_PROCESSING_RESPONSE = JSON.generate({
  "job" => { "id" => "job-abc", "status" => 2 }
})

JOB_CANCELLED_RESPONSE = JSON.generate({
  "job" => { "id" => "job-abc", "status" => 5, "error" => "Query was cancelled" }
})

def stub_post_with_job(base = BASE_URL)
  stub_request(:post, "#{base}/api/queries/123/results")
    .to_return(status: 200, body: JOB_RESPONSE)
end

class TestClientRequestBody < Minitest::Test
  def test_post_body_includes_max_age_zero_by_default
    req_stub = stub_request(:post, "#{BASE_URL}/api/queries/123/results")
      .with(body: JSON.generate({ "max_age" => 0, "parameters" => {} }))
      .to_return(status: 200, body: IMMEDIATE_RESULT_RESPONSE)
    stub_result_json
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    client.run_query(query_id: 123)
    assert_requested req_stub
  end

  def test_post_body_includes_params
    req_stub = stub_request(:post, "#{BASE_URL}/api/queries/123/results")
      .with(body: JSON.generate({ "max_age" => 0, "parameters" => { "project_id" => 6 } }))
      .to_return(status: 200, body: IMMEDIATE_RESULT_RESPONSE)
    stub_result_json
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    client.run_query(query_id: 123, params: { "project_id" => 6 })
    assert_requested req_stub
  end

  def test_post_body_includes_max_age_when_specified
    req_stub = stub_request(:post, "#{BASE_URL}/api/queries/123/results")
      .with(body: JSON.generate({ "max_age" => 3600, "parameters" => {} }))
      .to_return(status: 200, body: IMMEDIATE_RESULT_RESPONSE)
    stub_result_json
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    client.run_query(query_id: 123, max_age: 3600)
    assert_requested req_stub
  end

  def test_immediate_result_returns_json_string
    stub_immediate_result
    stub_result_json
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    result = client.run_query(query_id: 123, format: "json")
    assert_equal RESULT_JSON_RESPONSE, result
  end
end

class TestClientJobPolling < Minitest::Test
  def test_job_polling_success_returns_result
    stub_post_with_job
    stub_request(:get, "#{BASE_URL}/api/jobs/job-abc")
      .to_return(status: 200, body: JOB_DONE_RESPONSE)
    stub_result_json
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    result = client.run_query(query_id: 123, format: "json", poll_interval: 0)
    assert_equal RESULT_JSON_RESPONSE, result
  end

  def test_job_failure_raises_job_failed_error
    stub_post_with_job
    stub_request(:get, "#{BASE_URL}/api/jobs/job-abc")
      .to_return(status: 200, body: JOB_FAILED_RESPONSE)
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    err = assert_raises(RedashQuery::JobFailedError) do
      client.run_query(query_id: 123, poll_interval: 0)
    end
    assert_includes err.message, "division by zero"
  end

  def test_job_timeout_raises_timeout_error
    stub_post_with_job
    stub_request(:get, "#{BASE_URL}/api/jobs/job-abc")
      .to_return(status: 200, body: JOB_PROCESSING_RESPONSE)
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    _out, err = capture_io do
      assert_raises(RedashQuery::TimeoutError) do
        client.run_query(query_id: 123, timeout: 0, poll_interval: 0)
      end
    end
    assert_equal "Polling job job-abc...\n", err
  end

  def test_job_cancellation_raises_job_failed_error
    stub_post_with_job
    stub_request(:get, "#{BASE_URL}/api/jobs/job-abc")
      .to_return(status: 200, body: JOB_CANCELLED_RESPONSE)
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    err = assert_raises(RedashQuery::JobFailedError) do
      client.run_query(query_id: 123, poll_interval: 0)
    end
    assert_includes err.message, "cancelled"
  end
end

class TestClientFormat < Minitest::Test
  def test_csv_format_hits_csv_endpoint
    stub_immediate_result
    csv_stub = stub_result_csv
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    result = client.run_query(query_id: 123, format: "csv")
    assert_requested csv_stub
    assert_equal RESULT_CSV_RESPONSE, result
  end

  def test_json_format_hits_json_endpoint
    stub_immediate_result
    json_stub = stub_result_json
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    result = client.run_query(query_id: 123, format: "json")
    assert_requested json_stub
    assert_equal RESULT_JSON_RESPONSE, result
  end
end

class TestClientErrorHandling < Minitest::Test
  def test_401_raises_api_error
    stub_request(:post, "#{BASE_URL}/api/queries/123/results")
      .to_return(status: 401, body: '{"message":"Unauthorized"}')
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    assert_raises(RedashQuery::ApiError) do
      client.run_query(query_id: 123)
    end
  end

  def test_403_raises_api_error
    stub_request(:post, "#{BASE_URL}/api/queries/123/results")
      .to_return(status: 403, body: '{"message":"Forbidden"}')
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    assert_raises(RedashQuery::ApiError) do
      client.run_query(query_id: 123)
    end
  end

  def test_api_error_message_does_not_contain_api_key
    stub_request(:post, "#{BASE_URL}/api/queries/123/results")
      .to_return(status: 401, body: '{"message":"Unauthorized"}')
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    err = assert_raises(RedashQuery::ApiError) do
      client.run_query(query_id: 123)
    end
    refute_includes err.message, API_KEY
  end

  def test_500_raises_api_error_with_status
    stub_request(:post, "#{BASE_URL}/api/queries/123/results")
      .to_return(status: 500, body: "Internal Server Error")
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    err = assert_raises(RedashQuery::ApiError) do
      client.run_query(query_id: 123)
    end
    assert_includes err.message, "500"
  end

  def test_network_error_raises_api_error
    stub_request(:post, "#{BASE_URL}/api/queries/123/results")
      .to_raise(SocketError.new("getaddrinfo: nodename nor servname provided"))
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    err = assert_raises(RedashQuery::ApiError) do
      client.run_query(query_id: 123)
    end
    assert_includes err.message, "Network error"
  end
end

class TestClientListDatasources < Minitest::Test
  def test_list_datasources_returns_parsed_array
    stub_request(:get, "#{BASE_URL}/api/data_sources")
      .to_return(status: 200, body: DATASOURCES_RESPONSE, headers: { "Content-Type" => "application/json" })
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    result = client.list_datasources
    assert_equal 2, result.length
    assert_equal 1,          result[0]["id"]
    assert_equal "primary_db", result[0]["name"]
  end

  def test_list_datasources_401_raises_api_error
    stub_request(:get, "#{BASE_URL}/api/data_sources")
      .to_return(status: 401, body: '{"message":"Unauthorized"}')
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    assert_raises(RedashQuery::ApiError) { client.list_datasources }
  end
end

class TestClientCreateQuery < Minitest::Test
  def test_create_query_sends_correct_body
    req_stub = stub_request(:post, "#{BASE_URL}/api/queries")
      .with(body: JSON.generate({
        "name"           => "test query",
        "query"          => "SELECT 1",
        "data_source_id" => 1,
        "description"    => ""
      }))
      .to_return(status: 200, body: CREATE_QUERY_RESPONSE, headers: { "Content-Type" => "application/json" })
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    client.create_query(name: "test query", sql: "SELECT 1", datasource_id: 1)
    assert_requested req_stub
  end

  def test_create_query_returns_id_and_name
    stub_request(:post, "#{BASE_URL}/api/queries")
      .to_return(status: 200, body: CREATE_QUERY_RESPONSE, headers: { "Content-Type" => "application/json" })
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    result = client.create_query(name: "Recent records", sql: "SELECT 1", datasource_id: 1)
    assert_equal 657,           result["id"]
    assert_equal "Recent records", result["name"]
  end

  def test_create_query_with_description_sends_description
    req_stub = stub_request(:post, "#{BASE_URL}/api/queries")
      .with(body: JSON.generate({
        "name"           => "test",
        "query"          => "SELECT 1",
        "data_source_id" => 1,
        "description"    => "Records created today"
      }))
      .to_return(status: 200, body: CREATE_QUERY_RESPONSE, headers: { "Content-Type" => "application/json" })
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    client.create_query(name: "test", sql: "SELECT 1", datasource_id: 1, description: "Records created today")
    assert_requested req_stub
  end

  def test_create_query_401_raises_api_error
    stub_request(:post, "#{BASE_URL}/api/queries")
      .to_return(status: 401, body: '{"message":"Unauthorized"}')
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    assert_raises(RedashQuery::ApiError) do
      client.create_query(name: "test", sql: "SELECT 1", datasource_id: 1)
    end
  end
end

class TestClientStatus < Minitest::Test
  def test_query_status_returns_hash
    stub_request(:get, "#{BASE_URL}/api/queries/123")
      .to_return(status: 200, body: QUERY_STATUS_RESPONSE, headers: { "Content-Type" => "application/json" })
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    result = client.query_status(query_id: 123)
    assert_equal 123,            result["id"]
    assert_equal "Active Query", result["name"]
    assert_equal false,          result["is_archived"]
  end

  def test_query_status_archived_query
    stub_request(:get, "#{BASE_URL}/api/queries/123")
      .to_return(status: 200, body: QUERY_STATUS_ARCHIVED_RESPONSE, headers: { "Content-Type" => "application/json" })
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    result = client.query_status(query_id: 123)
    assert_equal true, result["is_archived"]
  end

  def test_query_status_404_raises_api_error
    stub_request(:get, "#{BASE_URL}/api/queries/123")
      .to_return(status: 404, body: '{"message":"Not found"}')
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    assert_raises(RedashQuery::ApiError) { client.query_status(query_id: 123) }
  end
end

class TestClientArchive < Minitest::Test
  def test_archive_query_sends_delete
    del_stub = stub_request(:delete, "#{BASE_URL}/api/queries/123")
      .to_return(status: 204, body: "")
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    client.archive_query(query_id: 123)
    assert_requested del_stub
  end

  def test_archive_query_404_raises_api_error
    stub_request(:delete, "#{BASE_URL}/api/queries/123")
      .to_return(status: 404, body: '{"message":"Not found"}')
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    assert_raises(RedashQuery::ApiError) do
      client.archive_query(query_id: 123)
    end
  end

  def test_archive_query_401_raises_api_error
    stub_request(:delete, "#{BASE_URL}/api/queries/123")
      .to_return(status: 401, body: '{"message":"Unauthorized"}')
    client = RedashQuery::Client.new(base_url: BASE_URL, api_key: API_KEY)
    assert_raises(RedashQuery::ApiError) do
      client.archive_query(query_id: 123)
    end
  end
end

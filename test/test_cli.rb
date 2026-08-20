require_relative "test_helper"
require "tmpdir"

class TestCLIEnvValidation < Minitest::Test
  def setup
    @orig_base_url = ENV["REDASH_BASE_URL"]
    @orig_api_key  = ENV["REDASH_API_KEY"]
    ENV.delete("REDASH_BASE_URL")
    ENV.delete("REDASH_API_KEY")
  end

  def teardown
    ENV["REDASH_BASE_URL"] = @orig_base_url
    ENV["REDASH_API_KEY"]  = @orig_api_key
  end

  def test_missing_base_url_raises_config_error
    ENV["REDASH_API_KEY"] = "key"
    cli = RedashQuery::CLI.new
    assert_raises(RedashQuery::ConfigError) do
      cli.send(:run_query, ["123"])
    end
  end

  def test_missing_api_key_raises_config_error
    ENV["REDASH_BASE_URL"] = "https://redash.example.com"
    cli = RedashQuery::CLI.new
    assert_raises(RedashQuery::ConfigError) do
      cli.send(:run_query, ["123"])
    end
  end

  def test_missing_both_raises_config_error
    cli = RedashQuery::CLI.new
    assert_raises(RedashQuery::ConfigError) do
      cli.send(:run_query, ["123"])
    end
  end
end

class TestCLIParamsValidation < Minitest::Test
  def test_invalid_json_params_raises_params_error
    cli = RedashQuery::CLI.new
    assert_raises(RedashQuery::ParamsError) do
      cli.send(:parse_options, ["--params", "{invalid json}"])
    end
  end

  def test_valid_json_params_parse_correctly
    cli = RedashQuery::CLI.new
    options = cli.send(:parse_options, ["--params", '{"project_id":6}'])
    assert_equal({ "project_id" => 6 }, options[:params])
  end

  def test_invalid_json_error_does_not_repeat_parameter_value
    sensitive_value = '{"account":"private-value"'
    cli = RedashQuery::CLI.new

    error = assert_raises(RedashQuery::ParamsError) do
      cli.send(:parse_options, ["--params", sensitive_value])
    end

    assert_equal "--params is not valid JSON", error.message
  end

  def test_negative_max_age_is_rejected
    cli = RedashQuery::CLI.new

    error = assert_raises(RedashQuery::Error) do
      cli.send(:parse_options, ["--max-age", "-1"])
    end

    assert_includes error.message, "--max-age"
  end

  def test_negative_timeout_is_rejected
    cli = RedashQuery::CLI.new

    error = assert_raises(RedashQuery::Error) do
      cli.send(:parse_options, ["--timeout", "-1"])
    end

    assert_includes error.message, "--timeout"
  end

  def test_negative_poll_interval_is_rejected
    cli = RedashQuery::CLI.new

    error = assert_raises(RedashQuery::Error) do
      cli.send(:parse_options, ["--poll-interval", "-1"])
    end

    assert_includes error.message, "--poll-interval"
  end

  def test_zero_numeric_options_are_accepted
    cli = RedashQuery::CLI.new
    options = cli.send(:parse_options, [
      "--max-age", "0", "--timeout", "0", "--poll-interval", "0"
    ])

    assert_equal 0, options[:max_age]
    assert_equal 0, options[:timeout]
    assert_equal 0, options[:poll_interval]
  end
end

class TestCLIArgumentErrors < Minitest::Test
  def setup
    WebMock.reset!
    @orig_base_url = ENV["REDASH_BASE_URL"]
    @orig_api_key  = ENV["REDASH_API_KEY"]
    ENV["REDASH_BASE_URL"] = "https://redash.example.com"
    ENV["REDASH_API_KEY"]  = "test_key"
  end

  def teardown
    ENV["REDASH_BASE_URL"] = @orig_base_url
    ENV["REDASH_API_KEY"]  = @orig_api_key
    WebMock.reset!
  end

  def test_unknown_option_exits_cleanly
    exit_error = nil
    out, err = capture_io do
      exit_error = assert_raises(SystemExit) do
        RedashQuery::CLI.run(["run", "123", "--unknown"])
      end
    end

    assert_equal 1, exit_error.status
    assert_equal "", out
    assert_includes err, "invalid option"
    assert_equal 1, err.lines.length
  end

  def test_missing_option_value_exits_cleanly
    exit_error = nil
    out, err = capture_io do
      exit_error = assert_raises(SystemExit) do
        RedashQuery::CLI.run(["run", "123", "--timeout"])
      end
    end

    assert_equal 1, exit_error.status
    assert_equal "", out
    assert_includes err, "missing argument"
    assert_equal 1, err.lines.length
  end

  def test_unknown_create_option_exits_cleanly
    exit_error = nil
    out, err = capture_io do
      exit_error = assert_raises(SystemExit) do
        RedashQuery::CLI.run(["create", "--unknown"])
      end
    end

    assert_equal 1, exit_error.status
    assert_equal "", out
    assert_includes err, "invalid option"
    assert_equal 1, err.lines.length
  end

  def test_zero_query_id_is_rejected_before_any_request
    exit_error = nil
    _out, err = capture_io do
      exit_error = assert_raises(SystemExit) do
        RedashQuery::CLI.run(["run", "0"])
      end
    end

    assert_equal 1, exit_error.status
    assert_includes err, "positive integer"
    assert_not_requested :any, /redash/
  end

  def test_zero_status_query_id_is_rejected_before_any_request
    assert_zero_query_id_rejected("status")
  end

  def test_zero_archive_query_id_is_rejected_before_any_request
    assert_zero_query_id_rejected("archive")
  end

  private

  def assert_zero_query_id_rejected(command)
    exit_error = nil
    _out, err = capture_io do
      exit_error = assert_raises(SystemExit) do
        RedashQuery::CLI.run([command, "0"])
      end
    end

    assert_equal 1, exit_error.status
    assert_includes err, "positive integer"
    assert_not_requested :any, /redash/
  end
end

class TestCLIOutputFile < Minitest::Test
  def setup
    @orig_base_url = ENV["REDASH_BASE_URL"]
    @orig_api_key  = ENV["REDASH_API_KEY"]
    ENV["REDASH_BASE_URL"] = "https://redash.example.com"
    ENV["REDASH_API_KEY"]  = "test_key"
  end

  def teardown
    ENV["REDASH_BASE_URL"] = @orig_base_url
    ENV["REDASH_API_KEY"]  = @orig_api_key
  end

  def test_output_file_writes_result
    stub_request(:post, "https://redash.example.com/api/queries/42/results")
      .to_return(
        status: 200,
        body: JSON.generate({ "query_result" => { "id" => 99 } })
      )
    stub_request(:get, "https://redash.example.com/api/query_results/99.csv")
      .to_return(status: 200, body: "col\nval\n")

    original_umask = File.umask(0)
    begin
      Dir.mktmpdir do |dir|
        outfile = File.join(dir, "result.csv")
        RedashQuery::CLI.run(["run", "42", "--format", "csv", "--output", outfile])
        assert File.exist?(outfile), "Output file was not created"
        assert_equal "col\nval\n", File.read(outfile)
        assert_equal 0o600, File.stat(outfile).mode & 0o777
      end
    ensure
      File.umask(original_umask)
    end
  end

  def test_existing_output_file_is_not_overwritten_by_default
    WebMock.reset!

    Dir.mktmpdir do |dir|
      outfile = File.join(dir, "result.csv")
      File.write(outfile, "existing\n")

      exit_error = nil
      _out, err = capture_io do
        exit_error = assert_raises(SystemExit) do
          RedashQuery::CLI.run(["run", "42", "--format", "csv", "--output", outfile])
        end
      end

      assert_equal 1, exit_error.status
      assert_includes err, "already exists"
      assert_equal "existing\n", File.read(outfile)
      assert_not_requested :any, /redash/
    end
  end

  def test_force_overwrites_output_file_with_private_permissions
    stub_request(:post, "https://redash.example.com/api/queries/42/results")
      .to_return(
        status: 200,
        body: JSON.generate({ "query_result" => { "id" => 99 } })
      )
    stub_request(:get, "https://redash.example.com/api/query_results/99.csv")
      .to_return(status: 200, body: "col\nnew\n")

    Dir.mktmpdir do |dir|
      outfile = File.join(dir, "result.csv")
      File.write(outfile, "existing\n")
      File.chmod(0o644, outfile)

      RedashQuery::CLI.run([
        "run", "42", "--format", "csv", "--output", outfile, "--force"
      ])

      assert_equal "col\nnew\n", File.read(outfile)
      assert_equal 0o600, File.stat(outfile).mode & 0o777
    end
  end
end

class TestCLICreateValidation < Minitest::Test
  def test_missing_file_raises_error
    cli = RedashQuery::CLI.new
    err = assert_raises(RedashQuery::Error) do
      cli.send(:parse_create_options, ["--name", "test", "--datasource-name", "primary_db"])
    end
    assert_includes err.message, "--file is required"
  end

  def test_missing_name_raises_error
    cli = RedashQuery::CLI.new
    err = assert_raises(RedashQuery::Error) do
      cli.send(:parse_create_options, ["--file", "/tmp/q.sql", "--datasource-name", "primary_db"])
    end
    assert_includes err.message, "--name is required"
  end

  def test_missing_datasource_name_raises_error
    cli = RedashQuery::CLI.new
    err = assert_raises(RedashQuery::Error) do
      cli.send(:parse_create_options, ["--file", "/tmp/q.sql", "--name", "test"])
    end
    assert_includes err.message, "--datasource-name is required"
  end
end

class TestCLICreateCommand < Minitest::Test
  def setup
    @orig_base_url = ENV["REDASH_BASE_URL"]
    @orig_api_key  = ENV["REDASH_API_KEY"]
    ENV["REDASH_BASE_URL"] = "https://redash.example.com"
    ENV["REDASH_API_KEY"]  = "test_key"
  end

  def teardown
    ENV["REDASH_BASE_URL"] = @orig_base_url
    ENV["REDASH_API_KEY"]  = @orig_api_key
  end

  def test_unreadable_file_raises_error
    cli = RedashQuery::CLI.new
    err = assert_raises(RedashQuery::Error) do
      cli.send(:create_query_cmd, [
        "--file", "/nonexistent/path.sql",
        "--name", "test",
        "--datasource-name", "primary_db"
      ])
    end
    assert_includes err.message, "cannot read file"
    assert_includes err.message, "/nonexistent/path.sql"
  end

  def test_datasource_not_found_raises_error_with_available_list
    stub_request(:get, "https://redash.example.com/api/data_sources")
      .to_return(status: 200, body: DATASOURCES_RESPONSE, headers: { "Content-Type" => "application/json" })

    Dir.mktmpdir do |dir|
      sql_file = File.join(dir, "q.sql")
      File.write(sql_file, "SELECT 1")

      cli = RedashQuery::CLI.new
      err = assert_raises(RedashQuery::Error) do
        cli.send(:create_query_cmd, [
          "--file", sql_file,
          "--name", "test",
          "--datasource-name", "Unknown"
        ])
      end
      assert_includes err.message, "Unknown"
      assert_includes err.message, "primary_db"
      assert_includes err.message, "analytics_db"
    end
  end

  def test_create_outputs_json_with_id_name_url
    stub_request(:get, "https://redash.example.com/api/data_sources")
      .to_return(status: 200, body: DATASOURCES_RESPONSE, headers: { "Content-Type" => "application/json" })
    stub_request(:post, "https://redash.example.com/api/queries")
      .to_return(status: 200, body: CREATE_QUERY_RESPONSE, headers: { "Content-Type" => "application/json" })

    Dir.mktmpdir do |dir|
      sql_file = File.join(dir, "q.sql")
      File.write(sql_file, "SELECT 1")

      out, _err = capture_io do
        RedashQuery::CLI.run([
          "create",
          "--file", sql_file,
          "--name", "Recent records",
          "--datasource-name", "primary_db"
        ])
      end

      parsed = JSON.parse(out)
      assert_equal 657,                                               parsed["id"]
      assert_equal "Recent records",                                     parsed["name"]
      assert_equal "https://redash.example.com/queries/657",          parsed["url"]
    end
  end
end

class TestCLIStatus < Minitest::Test
  def setup
    @orig_base_url = ENV["REDASH_BASE_URL"]
    @orig_api_key  = ENV["REDASH_API_KEY"]
    ENV["REDASH_BASE_URL"] = "https://redash.example.com"
    ENV["REDASH_API_KEY"]  = "test_key"
  end

  def teardown
    ENV["REDASH_BASE_URL"] = @orig_base_url
    ENV["REDASH_API_KEY"]  = @orig_api_key
    WebMock.reset!
  end

  def test_status_outputs_json_to_stdout
    stub_request(:get, "https://redash.example.com/api/queries/123")
      .to_return(status: 200, body: QUERY_STATUS_RESPONSE, headers: { "Content-Type" => "application/json" })
    out, _err = capture_io { RedashQuery::CLI.run(["status", "123"]) }
    parsed = JSON.parse(out)
    assert_equal 123,            parsed["id"]
    assert_equal "Active Query", parsed["name"]
    assert_equal false,          parsed["is_archived"]
  end

  def test_status_archived_query_shows_is_archived_true
    stub_request(:get, "https://redash.example.com/api/queries/123")
      .to_return(status: 200, body: QUERY_STATUS_ARCHIVED_RESPONSE, headers: { "Content-Type" => "application/json" })
    out, _err = capture_io { RedashQuery::CLI.run(["status", "123"]) }
    parsed = JSON.parse(out)
    assert_equal true, parsed["is_archived"]
  end

  def test_status_404_exits_with_error
    stub_request(:get, "https://redash.example.com/api/queries/123")
      .to_return(status: 404, body: '{"message":"Not found"}')
    e = assert_raises(SystemExit) do
      capture_io { RedashQuery::CLI.run(["status", "123"]) }
    end
    assert_equal 1, e.status
  end

  def test_status_missing_query_id_exits_with_error
    e = assert_raises(SystemExit) do
      capture_io { RedashQuery::CLI.run(["status"]) }
    end
    assert_equal 1, e.status
  end
end

class TestCLIArchive < Minitest::Test
  def setup
    @orig_base_url = ENV["REDASH_BASE_URL"]
    @orig_api_key  = ENV["REDASH_API_KEY"]
    @orig_stdin    = $stdin
    ENV["REDASH_BASE_URL"] = "https://redash.example.com"
    ENV["REDASH_API_KEY"]  = "test_key"
  end

  def teardown
    ENV["REDASH_BASE_URL"] = @orig_base_url
    ENV["REDASH_API_KEY"]  = @orig_api_key
    $stdin = @orig_stdin
    WebMock.reset!
  end

  def test_archive_y_sends_delete
    $stdin = StringIO.new("y\n")
    del_stub = stub_request(:delete, "https://redash.example.com/api/queries/123")
      .to_return(status: 204, body: "")
    capture_io { RedashQuery::CLI.run(["archive", "123"]) }
    assert_requested del_stub
  end

  def test_archive_yes_sends_delete
    $stdin = StringIO.new("yes\n")
    del_stub = stub_request(:delete, "https://redash.example.com/api/queries/123")
      .to_return(status: 204, body: "")
    capture_io { RedashQuery::CLI.run(["archive", "123"]) }
    assert_requested del_stub
  end

  def test_archive_n_does_not_send_delete
    $stdin = StringIO.new("n\n")
    e = assert_raises(SystemExit) do
      capture_io { RedashQuery::CLI.run(["archive", "123"]) }
    end
    assert_equal 0, e.status
  end

  def test_archive_empty_does_not_send_delete
    $stdin = StringIO.new("\n")
    e = assert_raises(SystemExit) do
      capture_io { RedashQuery::CLI.run(["archive", "123"]) }
    end
    assert_equal 0, e.status
  end

  def test_archive_missing_query_id_exits_with_error
    $stdin = StringIO.new("")
    e = assert_raises(SystemExit) do
      capture_io { RedashQuery::CLI.run(["archive"]) }
    end
    assert_equal 1, e.status
  end
end

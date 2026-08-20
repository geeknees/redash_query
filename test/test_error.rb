require_relative "test_helper"

class TestError < Minitest::Test
  def test_config_error_is_redash_error
    assert RedashQuery::ConfigError.ancestors.include?(RedashQuery::Error)
  end

  def test_api_error_is_redash_error
    assert RedashQuery::ApiError.ancestors.include?(RedashQuery::Error)
  end

  def test_job_failed_error_is_redash_error
    assert RedashQuery::JobFailedError.ancestors.include?(RedashQuery::Error)
  end

  def test_timeout_error_is_redash_error
    assert RedashQuery::TimeoutError.ancestors.include?(RedashQuery::Error)
  end

  def test_params_error_is_redash_error
    assert RedashQuery::ParamsError.ancestors.include?(RedashQuery::Error)
  end

  def test_all_are_standard_error
    assert RedashQuery::Error.ancestors.include?(StandardError)
  end
end

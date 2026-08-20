# ABOUTME: Custom exception hierarchy for redash_query.
# All errors are subclasses of RedashQuery::Error for easy rescue at CLI boundary.
module RedashQuery
  class Error          < StandardError; end
  class ConfigError    < Error; end
  class ApiError       < Error; end
  class JobFailedError < Error; end
  class TimeoutError   < Error; end
  class ParamsError    < Error; end
end

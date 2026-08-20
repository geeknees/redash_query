# ABOUTME: Test setup — loads minitest, webmock, and all lib files.
# All HTTP is stubbed; real Redash connections are prohibited in tests.
require "minitest/autorun"
require "webmock/minitest"
require "json"
require_relative "../lib/redash_query/error"
require_relative "../lib/redash_query/client"
require_relative "../lib/redash_query/cli"

DATASOURCES_RESPONSE = JSON.generate([
  { "id" => 1, "name" => "primary_db" },
  { "id" => 2, "name" => "analytics_db" }
])

CREATE_QUERY_RESPONSE = JSON.generate({
  "id" => 657,
  "name" => "Recent records"
})

QUERY_STATUS_RESPONSE = JSON.generate({
  "id"          => 123,
  "name"        => "Active Query",
  "description" => "test",
  "is_archived" => false
})

QUERY_STATUS_ARCHIVED_RESPONSE = JSON.generate({
  "id"          => 123,
  "name"        => "Old Query",
  "description" => "",
  "is_archived" => true
})

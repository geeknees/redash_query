# frozen_string_literal: true

require_relative "lib/redash_query/version"

Gem::Specification.new do |spec|
  spec.name        = "redash_query"
  spec.version     = RedashQuery::VERSION
  spec.authors     = ["Masumi Kawasaki"]

  spec.summary     = "Unofficial Ruby CLI for executing saved Redash queries"
  spec.description = "An unofficial command-line tool for running, creating, and archiving saved Redash queries " \
                      "via the Redash API, with JSON/CSV output for use in scripts and automation."
  spec.homepage    = "https://github.com/geeknees/redash_query"
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.3"

  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues"
  }

  spec.files         = Dir["lib/**/*.rb", "exe/*", "README.md", "LICENSE"]
  spec.bindir        = "exe"
  spec.executables   = ["redash_query"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency "webmock", "~> 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
end

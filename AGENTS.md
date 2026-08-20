<!-- ABOUTME: Contributor guidance for the public redash_query repository. -->
<!-- ABOUTME: Keeps development test-first, generic, and safe for public history. -->

# AGENTS.md

- Keep examples generic. Do not add real Redash hosts, datasource names, query data, credentials, or personal paths.
- Make behavior changes test-first and keep all HTTP tests isolated with WebMock.
- Run CLI probes only with stubbed HTTP and sanitized test credentials; never inherit real Redash settings.
- Run `bundle exec rake test`, lint checks, `gem build redash_query.gemspec`, and the full privacy scan before release.
- Do not commit `.env` files, query results, generated gems, or temporary output.
- Match the existing Ruby style and add two brief `ABOUTME` comments to new hand-written source files when comments are idiomatic.

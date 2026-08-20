# redash_query

Unofficial Ruby CLI and client for running and managing saved Redash queries from scripts and automation.

This project is not affiliated with or endorsed by the Redash maintainers.

## Requirements

- Ruby 3.3 or later
- Bundler for development

## Installation

```bash
git clone https://github.com/geeknees/redash_query.git
cd redash_query
bundle install
exe/redash_query --help
```

### Installing as a gem (local only, not published)

This gem is not published to RubyGems.org. To get a `redash_query` command
on your PATH without publishing, build and install it locally:

```bash
gem build redash_query.gemspec
gem install ./redash_query-0.1.0.gem
```

```bash
which redash_query
redash_query --help
```

Re-run `gem build` + `gem install` after any code change — it does not
auto-update. To remove it: `gem uninstall redash_query`.

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `REDASH_BASE_URL` | Yes | Base URL of your Redash instance (e.g. `https://redash.example.com`) |
| `REDASH_API_KEY` | Yes | Your Redash API key (User Settings → API Key) |

Use HTTPS so the API key is encrypted in transit. Plain HTTP is accepted only
for literal loopback hosts (`localhost`, `127.0.0.1`, and `::1`) during local
development. A trailing slash is handled automatically.

Never commit API keys or include them in issues, logs, or examples.

## Usage

### Basic query

```bash
export REDASH_BASE_URL="https://redash.example.com"
export REDASH_API_KEY="your_api_key"

exe/redash_query run 123
```

### Create a new query

```bash
exe/redash_query create \
  --file /tmp/my_query.sql \
  --name "Recent records" \
  --datasource-name "primary_db"
```

Output (stdout):
```json
{"id":657,"name":"Recent records","url":"https://redash.example.com/queries/657"}
```

With optional description:
```bash
exe/redash_query create \
  --file /tmp/my_query.sql \
  --name "Recent records" \
  --datasource-name "primary_db" \
  --description "Records created today"
```

### With parameters

```bash
exe/redash_query run 123 --params '{"project_id":6,"from":"2026-06-01","to":"2026-06-30"}'
```

### CSV output to file

```bash
exe/redash_query run 123 \
  --params '{"project_id":6,"from":"2026-06-01","to":"2026-06-30"}' \
  --format csv \
  --output result.csv
```

New output files are created with mode `0600`. Existing files are refused by
default; pass `--force` only when replacing the file is intentional.

### Check query status

```bash
exe/redash_query status 123
```

### Archive a query

```bash
exe/redash_query archive 123
```

`archive` changes the Redash instance. It displays a confirmation prompt and
does nothing unless you enter `y` or `yes`.

### All options

```
exe/redash_query run QUERY_ID [options]

  --params JSON        Query parameters as JSON string
  --format json|csv    Output format (default: json)
  --output FILE        Write output to file (default: stdout)
  --force              Overwrite an existing output file
  --max-age N          Nonnegative cache age in seconds (default: 0 = always re-run)
  --timeout N          Nonnegative job polling timeout in seconds (default: 120)
  --poll-interval N    Nonnegative polling interval in seconds (default: 1)
  -h, --help           Show help
```

### create options

```
exe/redash_query create [options]

  --file PATH              SQL file path (required)
  --name NAME              Query name in Redash (required)
  --datasource-name NAME   Datasource name (required, e.g. "primary_db")
  --description TEXT       Query description (optional)
  -h, --help               Show help
```

## Calling from an automation script

```bash
result=$(exe/redash_query run 42 \
  --params '{"project_id":6}' \
  --format csv)
```

Or write directly to a file and pass the path to downstream tools:

```bash
exe/redash_query run 42 \
  --params '{"project_id":6}' \
  --format csv \
  --output report.csv
```

## Running Tests

```bash
bundle exec rake test
gem build redash_query.gemspec
```

## Troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `REDASH_BASE_URL is not set` | Env var missing | Export `REDASH_BASE_URL` |
| `REDASH_API_KEY is not set` | Env var missing | Export `REDASH_API_KEY` |
| `REDASH_BASE_URL must use HTTPS ...` | Remote URL uses plain HTTP | Change the URL to HTTPS |
| `output file already exists: ...` | Refusing to overwrite output | Choose a new path or pass `--force` intentionally |
| `Unauthorized: check your Redash API key configuration` | Invalid or expired API key | Regenerate key in Redash User Settings |
| `Not found: query or resource does not exist` | Wrong query ID | Verify the query ID in Redash |
| `Query timed out after N seconds` | Query ran too long | Use `--timeout 300` to extend |
| `--params is not valid JSON` | JSON syntax error | Validate JSON with `echo '...' \| jq .` |
| `datasource "X" not found. Available: ...` | Datasource name mismatch | Use exact name from the available list |
| `cannot read file: /path/to/file.sql` | File missing or unreadable | Check path and permissions |

## License

[MIT](LICENSE)

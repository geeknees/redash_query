# ABOUTME: CLI entry point — parses arguments, validates env vars, delegates to Client.
# stdout carries result data only; stderr carries progress and error messages.
require "optparse"
require "json"
require_relative "error"
require_relative "client"

module RedashQuery
  class CLI
    DEFAULTS = {
      format:        "json",
      max_age:       0,
      timeout:       120,
      poll_interval: 1,
      output:        nil,
      force:         false,
      params:        {}
    }.freeze

    def self.run(argv)
      new.run(argv)
    end

    def run(argv)
      argv = argv.dup
      subcommand = argv.shift
      case subcommand
      when "run"
        run_query(argv)
      when "create"
        create_query_cmd(argv)
      when "archive"
        archive_query_cmd(argv)
      when "status"
        status_query_cmd(argv)
      when nil, "-h", "--help"
        $stdout.puts usage
      else
        $stderr.puts "Unknown subcommand: #{subcommand}"
        $stderr.puts usage
        exit 1
      end
    rescue Error, OptionParser::ParseError => e
      $stderr.puts "Error: #{e.message}"
      exit 1
    end

    private

    def run_query(argv)
      argv    = argv.dup
      options = parse_options(argv)
      query_id = argv.first

      unless query_id&.match?(/\A[1-9]\d*\z/)
        $stderr.puts "Error: QUERY_ID must be a positive integer"
        exit 1
      end

      validate_output_path!(options[:output], force: options[:force]) if options[:output]

      base_url = ENV["REDASH_BASE_URL"] or raise ConfigError, "REDASH_BASE_URL is not set"
      api_key  = ENV["REDASH_API_KEY"]  or raise ConfigError, "REDASH_API_KEY is not set"

      client = Client.new(base_url: base_url, api_key: api_key)
      result = client.run_query(
        query_id:      query_id.to_i,
        params:        options[:params],
        max_age:       options[:max_age],
        format:        options[:format],
        timeout:       options[:timeout],
        poll_interval: options[:poll_interval]
      )

      if options[:output]
        write_output_file(options[:output], result, force: options[:force])
      else
        $stdout.print result
      end
    end

    def parse_options(argv)
      options = DEFAULTS.dup

      parser = OptionParser.new do |opts|
        opts.on("--params JSON", "Query parameters as JSON") do |json|
          begin
            options[:params] = JSON.parse(json)
          rescue JSON::ParserError
            raise ParamsError, "--params is not valid JSON"
          end
        end

        opts.on("--format FORMAT", "Output format: json or csv (default: json)") do |f|
          unless %w[json csv].include?(f)
            raise Error, "--format must be json or csv"
          end
          options[:format] = f
        end

        opts.on("--output FILE", "Write output to file instead of stdout") do |f|
          options[:output] = f
        end

        opts.on("--force", "Overwrite an existing output file") do
          options[:force] = true
        end

        opts.on("--max-age N", Integer, "Cache age in seconds (default: 0)") do |n|
          raise Error, "--max-age must be 0 or greater" if n.negative?

          options[:max_age] = n
        end

        opts.on("--timeout N", Integer, "Polling timeout in seconds (default: 120)") do |n|
          raise Error, "--timeout must be 0 or greater" if n.negative?

          options[:timeout] = n
        end

        opts.on("--poll-interval N", Integer, "Polling interval in seconds (default: 1)") do |n|
          raise Error, "--poll-interval must be 0 or greater" if n.negative?

          options[:poll_interval] = n
        end

        opts.on("-h", "--help", "Show this help") do
          $stdout.puts opts
          exit 0
        end
      end

      parser.parse!(argv)
      options
    end

    def create_query_cmd(argv)
      argv    = argv.dup
      options = parse_create_options(argv)

      base_url = ENV["REDASH_BASE_URL"] or raise ConfigError, "REDASH_BASE_URL is not set"
      api_key  = ENV["REDASH_API_KEY"]  or raise ConfigError, "REDASH_API_KEY is not set"

      sql = begin
        File.read(options[:file])
      rescue Errno::ENOENT, Errno::EACCES
        raise Error, "cannot read file: #{options[:file]}"
      end

      client = Client.new(base_url: base_url, api_key: api_key)

      datasources = client.list_datasources
      ds = datasources.find { |d| d["name"] == options[:datasource_name] }
      unless ds
        available = datasources.map { |d| d["name"] }.join(", ")
        raise Error, "datasource \"#{options[:datasource_name]}\" not found. Available: #{available}"
      end

      result = client.create_query(
        name:          options[:name],
        sql:           sql,
        datasource_id: ds["id"],
        description:   options[:description] || ""
      )

      $stdout.puts JSON.generate({
        "id"   => result["id"],
        "name" => result["name"],
        "url"  => "#{base_url.chomp("/")}/queries/#{result["id"]}"
      })
    end

    def status_query_cmd(argv)
      query_id = argv.first

      unless query_id&.match?(/\A[1-9]\d*\z/)
        $stderr.puts "Error: QUERY_ID must be a positive integer"
        exit 1
      end

      base_url = ENV["REDASH_BASE_URL"] or raise ConfigError, "REDASH_BASE_URL is not set"
      api_key  = ENV["REDASH_API_KEY"]  or raise ConfigError, "REDASH_API_KEY is not set"

      client = Client.new(base_url: base_url, api_key: api_key)
      data   = client.query_status(query_id: query_id.to_i)

      $stdout.puts JSON.generate({
        "id"          => data["id"],
        "name"        => data["name"],
        "description" => data["description"],
        "is_archived" => data["is_archived"]
      })
    end

    def archive_query_cmd(argv)
      query_id = argv.first

      unless query_id&.match?(/\A[1-9]\d*\z/)
        $stderr.puts "Error: QUERY_ID must be a positive integer"
        exit 1
      end

      base_url = ENV["REDASH_BASE_URL"] or raise ConfigError, "REDASH_BASE_URL is not set"
      api_key  = ENV["REDASH_API_KEY"]  or raise ConfigError, "REDASH_API_KEY is not set"

      $stderr.print "Archive query #{query_id}? [y/N]: "
      answer = $stdin.gets.to_s.strip.downcase

      unless %w[y yes].include?(answer)
        $stderr.puts "Cancelled."
        exit 0
      end

      client = Client.new(base_url: base_url, api_key: api_key)
      client.archive_query(query_id: query_id.to_i)
      $stderr.puts "Archived query #{query_id}."
    end

    def parse_create_options(argv)
      options = { file: nil, name: nil, datasource_name: nil, description: nil }

      parser = OptionParser.new do |opts|
        opts.on("--file PATH", "SQL file path") { |v| options[:file] = v }
        opts.on("--name NAME", "Query name")    { |v| options[:name] = v }
        opts.on("--datasource-name NAME", "Datasource name") { |v| options[:datasource_name] = v }
        opts.on("--description TEXT", "Query description")   { |v| options[:description] = v }
        opts.on("-h", "--help", "Show this help") { $stdout.puts opts; exit 0 }
      end

      parser.parse!(argv)

      raise Error, "--file is required"            unless options[:file]
      raise Error, "--name is required"            unless options[:name]
      raise Error, "--datasource-name is required" unless options[:datasource_name]

      options
    end

    def validate_output_path!(path, force:)
      return if force || !File.exist?(path)

      raise Error, "output file already exists: #{path} (use --force to overwrite)"
    end

    def write_output_file(path, result, force:)
      flags = File::WRONLY | File::CREAT
      flags |= force ? File::TRUNC : File::EXCL

      File.open(path, flags, 0o600) do |file|
        file.chmod(0o600)
        file.write(result)
      end
    rescue Errno::EEXIST
      raise Error, "output file already exists: #{path} (use --force to overwrite)"
    rescue SystemCallError => e
      raise Error, "cannot write output file: #{path} (#{e.message})"
    end

    def usage
      <<~USAGE.chomp
        Usage:
          redash_query run QUERY_ID [--params JSON] [--format json|csv] [--output FILE] [--force] [--max-age N] [--timeout N] [--poll-interval N]
          redash_query create --file PATH --name NAME --datasource-name NAME [--description TEXT]
          redash_query archive QUERY_ID
          redash_query status QUERY_ID
      USAGE
    end
  end
end

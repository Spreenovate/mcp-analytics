require "net/http"
require "uri"
require "json"

# Thin HTTP client for the ClickHouse native HTTP interface.
# Queries use the JSONCompact format because it's both compact and preserves
# column ordering without needing row-object names on the wire.
module ClickHouse
  class Error < StandardError; end
  class QueryError < Error; end

  class Client
    DEFAULT_TIMEOUT = 10

    def initialize(url: nil, user: nil, password: nil, database: nil, timeout: DEFAULT_TIMEOUT)
      @url      = URI.parse(url || ENV.fetch("CLICKHOUSE_URL", "http://localhost:8123"))
      @user     = user || ENV["CLICKHOUSE_USER"] || "default"
      @password = password || ENV["CLICKHOUSE_PASSWORD"].to_s
      @database = database || ENV.fetch("CLICKHOUSE_DB", "mcpa")
      @timeout  = timeout
    end

    # Returns an Array of Hashes, one per row, keyed by column name.
    # Bind parameters via ClickHouse's {name:Type} placeholders; values are passed
    # as `param_<name>` HTTP parameters which ClickHouse URL-escapes and quotes
    # correctly per the declared type.
    def query(sql, params: {}, types: {})
      # ClickHouse doesn't allow multi-statements by default, so database and
      # settings go via URL params — NOT inline SQL prefixes.
      qs = {
        "default_format" => "JSON",
        "database"       => @database,
        "use_query_cache" => "0"
      }
      params.each do |k, v|
        qs["param_#{k}"] = serialize_param(v, types[k])
      end

      uri = @url.dup
      uri.query = URI.encode_www_form(qs)

      req = Net::HTTP::Post.new(uri)
      req.basic_auth(@user, @password) if @user && !@user.empty?
      req["Content-Type"] = "text/plain; charset=utf-8"
      req.body = sql

      res = Net::HTTP.start(uri.host, uri.port,
                            use_ssl: uri.scheme == "https",
                            read_timeout: @timeout,
                            open_timeout: @timeout) { |http| http.request(req) }

      unless res.is_a?(Net::HTTPSuccess)
        raise QueryError, "clickhouse #{res.code}: #{res.body.to_s[0, 1024]}"
      end

      body = res.body.to_s
      return [] if body.empty?

      parsed = JSON.parse(body)
      parsed["data"] || []
    end

    def ping
      uri = @url.dup
      uri.path = "/ping"
      Net::HTTP.start(uri.host, uri.port,
                      use_ssl: uri.scheme == "https",
                      read_timeout: 2,
                      open_timeout: 2) do |http|
        res = http.get(uri.request_uri)
        res.is_a?(Net::HTTPSuccess)
      end
    rescue StandardError
      false
    end

    private

    def serialize_param(value, type)
      case value
      when Time, DateTime
        value.utc.strftime("%Y-%m-%d %H:%M:%S")
      when Date
        value.strftime("%Y-%m-%d")
      else
        value.to_s
      end
    end
  end

  def self.client
    @client ||= Client.new
  end

  def self.reset!
    @client = nil
  end
end

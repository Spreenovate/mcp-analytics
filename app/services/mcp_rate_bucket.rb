# Per-token sliding-window rate limiter backed by Rails.cache.
# 60 requests/minute per token is plenty for conversational MCP use and
# cheap to enforce this way. When we later swap in solid_cache (enabled by
# default in Rails 8) this transparently becomes SQLite-backed.
class McpRateBucket
  LIMIT  = 60
  WINDOW = 60 # seconds

  def self.acquire(token)
    new(token)
  end

  def initialize(token)
    @token = token
  end

  def allow!
    key = "mcp_rate:#{@token}"
    count = Rails.cache.increment(key, 1, expires_in: WINDOW)
    if count.nil?
      # increment returns nil if key didn't exist — initialize it.
      Rails.cache.write(key, 1, expires_in: WINDOW, raw: true)
      return true
    end
    count <= LIMIT
  end
end

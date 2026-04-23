# Simple Rails.cache-backed counter for rate-limiting.
# Returns true if the increment stayed within `limit` over `window` seconds.
class RateLimit
  def self.allow?(key:, limit:, window:)
    cache_key = "rl:#{key}"
    count = Rails.cache.increment(cache_key, 1, expires_in: window)
    if count.nil?
      Rails.cache.write(cache_key, 1, expires_in: window, raw: true)
      return true
    end
    count <= limit
  end
end

module Oauth
  # Centralised, sanitised PUBLIC_BASE_URL accessor.
  #
  # Defends against header-injection if the env var is ever set to a value
  # containing CR/LF (which would split the WWW-Authenticate header).
  module BaseUrl
    DEFAULT = "https://mcp-analytics.com".freeze

    def self.value
      raw = ENV.fetch("PUBLIC_BASE_URL", DEFAULT).to_s
      sanitised = raw.gsub(/[\r\n]/, "").strip
      sanitised.empty? ? DEFAULT : sanitised
    end
  end
end

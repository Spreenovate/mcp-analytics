module OauthCors
  extend ActiveSupport::Concern

  # claude.ai's MCP custom-connector flow makes the /oauth/token POST from
  # the browser via fetch() (NOT server-side) — so the call hits a CORS
  # preflight first. Without proper CORS headers we silently fail at the
  # preflight, and claude.ai never reaches our /oauth/token endpoint —
  # exact symptom in claude-ai-mcp issues #46, #163, #215.
  #
  # Discovery endpoints get hit from both server-side (claude.ai backend)
  # and browser-side (clients that probe). Always return permissive CORS
  # — these are public-by-design metadata documents.
  #
  # /oauth/register is server-side from claude.ai's backend, but other
  # OAuth-aware browser clients (cursor, custom MCP clients) may use it
  # from a browser context too. Same allowlist.
  #
  # /oauth/token is purely public-client + PKCE, no client secret. CORS
  # echoing the request Origin (with a default of `*`) is safe — there's
  # nothing in the response that needs cookie credentials.

  ALLOWED_ORIGIN_PATTERNS = [
    %r{\Ahttps://claude\.ai\z},
    %r{\Ahttps://[a-z0-9-]+\.claude\.ai\z},
    %r{\Ahttps://(?:www\.)?anthropic\.com\z},
    %r{\Ahttps://chatgpt\.com\z},
    %r{\Ahttps://[a-z0-9-]+\.chatgpt\.com\z},
    %r{\Ahttps://(?:www\.)?openai\.com\z},
    %r{\Ahttps?://localhost(?::\d+)?\z},
    %r{\Ahttps?://127\.0\.0\.1(?::\d+)?\z}
  ].freeze

  included do
    before_action :set_oauth_cors_headers
  end

  class_methods do
    # Routes config-side OPTIONS preflight to a no-op action that returns
    # 204 with the CORS headers from the before_action.
    def cors_preflight
      head :no_content
    end
  end

  private

  def set_oauth_cors_headers
    origin = request.headers["Origin"].to_s
    allow_origin =
      if origin.present? && ALLOWED_ORIGIN_PATTERNS.any? { |re| origin.match?(re) }
        origin
      else
        # Public metadata + token endpoints work without credentials. `*`
        # is fine and matches what cloudflare/workers-oauth-provider does.
        "*"
      end

    response.set_header("Access-Control-Allow-Origin", allow_origin)
    response.set_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    response.set_header("Access-Control-Allow-Headers", "Authorization, Content-Type, MCP-Protocol-Version")
    response.set_header("Access-Control-Max-Age", "86400")
    response.set_header("Vary", [ response.headers["Vary"], "Origin" ].compact.join(", "))
  end
end

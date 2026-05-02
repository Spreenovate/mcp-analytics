class McpController < ApplicationController
  # MCP is a JSON-RPC endpoint. Skip CSRF because clients are programmatic and
  # authenticate with a bearer token or URL token param, not a session cookie.
  skip_before_action :verify_authenticity_token, raise: false, only: [ :dispatch_rpc ]

  before_action :throttle_if_authenticated, only: [ :dispatch_rpc ]
  after_action  :advertise_oauth_resource, only: [ :dispatch_rpc, :info ]

  # POST /mcp
  def dispatch_rpc
    user = authenticate_from_request

    # If a token WAS presented but didn't authenticate, return 401 with an
    # error code so OAuth-aware clients trigger their re-auth flow.
    if user.nil? && bearer_token_presented?
      response.set_header(
        "WWW-Authenticate",
        %(Bearer error="invalid_token", resource_metadata="#{Oauth::BaseUrl.value}/.well-known/oauth-protected-resource")
      )
      return render(json: { jsonrpc: "2.0", id: nil,
                            error: { code: -32001, message: "Invalid or expired bearer token" } },
                    status: :unauthorized)
    end

    body = read_json_body
    return head(:bad_request) if body.nil?

    if body.is_a?(Array)
      responses = body.map { |r| Mcp::Server.new(user: user, request: request).handle(r) }.compact
      render json: responses
    else
      response = Mcp::Server.new(user: user, request: request).handle(body)
      if response.nil?
        head :accepted
      else
        render json: response
      end
    end
  end

  # GET /mcp — for clients that probe the endpoint.
  def info
    render json: {
      name: "mcp-analytics",
      description: "Web analytics over MCP.",
      transport: "streamable-http (JSON-RPC over POST)",
      auth: "OAuth 2.1 (PKCE) preferred. Discovery: /.well-known/oauth-protected-resource. Legacy: 'Authorization: Bearer <token>' or ?token=<token>. Without a token, only signup tools are exposed."
    }
  end

  private

  # Authenticates against either:
  #   - a new OauthAccessToken (Bearer header), or
  #   - the legacy users.api_token (Bearer header or ?token=).
  def authenticate_from_request
    if (header_token = bearer_token).present?
      if (oauth_token = OauthAccessToken.active.find_by(token: header_token))
        oauth_token.touch_used!
        return oauth_token.user
      end
      legacy = User.find_by(api_token: header_token)
      return legacy if legacy
    end

    if (query_token = params[:token].presence)
      return User.find_by(api_token: query_token)
    end

    nil
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    return nil unless header =~ /\ABearer\s+(.+)\z/i
    Regexp.last_match(1).strip
  end

  def bearer_token_presented?
    bearer_token.present? || params[:token].present?
  end

  # Per MCP spec (2025-06-18) + RFC 9728: every response advertises the
  # protected-resource metadata so OAuth-aware clients can discover the
  # authorization server and start the flow.
  def advertise_oauth_resource
    # Don't clobber a 401's invalid_token-tagged header.
    return if response.headers["WWW-Authenticate"].present?
    base = Oauth::BaseUrl.value
    response.set_header(
      "WWW-Authenticate",
      %(Bearer resource_metadata="#{base}/.well-known/oauth-protected-resource")
    )
  end

  def read_json_body
    raw = request.body.read
    return nil if raw.blank?
    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  def throttle_if_authenticated
    # Simple in-process throttling (60 req/min per user token).
    # Replaced with a proper rack-attack config in production if needed.
    token = bearer_token || params[:token].presence
    return if token.blank?

    bucket = McpRateBucket.acquire(token)
    return if bucket.allow!

    render json: {
      jsonrpc: "2.0", id: nil,
      error: { code: -32029, message: "Rate limited: 60 requests/minute per token." }
    }, status: :too_many_requests
  end
end

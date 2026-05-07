class McpController < ApplicationController
  include OauthCors
  # MCP is a JSON-RPC endpoint. Skip CSRF because clients are programmatic and
  # authenticate with a bearer token or URL token param, not a session cookie.
  # `:preflight` is the OPTIONS no-op for browser CORS preflight — also
  # session-less by definition.
  skip_before_action :verify_authenticity_token, raise: false, only: [ :dispatch_rpc, :preflight ]

  after_action :advertise_oauth_resource, only: [ :dispatch_rpc, :info ]

  def preflight
    head :no_content
  end

  # POST /mcp
  def dispatch_rpc
    auth = authenticate_from_request

    # MCP spec 2025-06-18 + RFC 9728: every unauthenticated request to a
    # protected resource returns 401 + WWW-Authenticate so that OAuth-aware
    # clients (claude.ai, etc.) auto-discover the authorization server and
    # start the flow. Tagging with `error="invalid_token"` only when a
    # token WAS presented gives clients useful feedback ("retry vs reauth").
    if auth.user.nil?
      error_tag = bearer_token_presented? ? %(error="invalid_token", ) : ""
      response.set_header(
        "WWW-Authenticate",
        %(Bearer #{error_tag}resource_metadata="#{Oauth::BaseUrl.value}/.well-known/oauth-protected-resource")
      )
      message = bearer_token_presented? ? "Invalid or expired bearer token" : "Authentication required"
      return render(json: { jsonrpc: "2.0", id: nil,
                            error: { code: -32001, message: message } },
                    status: :unauthorized)
    end

    # Rate-limit AFTER auth, keyed by user_id (not by raw token string).
    # Pre-auth keying let an attacker who knew a victim's token DoS the
    # victim's bucket from any IP. Post-auth keying ties consumption to
    # the actual account; a leaked-but-still-valid token can only burn
    # the same bucket the legitimate user shares, no cross-victim grief.
    return if rate_limit_exceeded?(auth.user)

    body = read_json_body
    return head(:bad_request) if body.nil?

    if body.is_a?(Array)
      responses = body.map { |r| Mcp::Server.new(auth: auth, request: request).handle(r) }.compact
      render json: responses
    else
      response = Mcp::Server.new(auth: auth, request: request).handle(body)
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
      auth: "OAuth 2.1 + PKCE. Discovery: /.well-known/oauth-protected-resource. All POST /mcp requests without a valid bearer token return 401."
    }
  end

  private

  # Authenticates against either:
  #   - a new OauthAccessToken (Bearer header), or
  #   - the legacy users.api_token (Bearer header or ?token=).
  #
  # Returns an Mcp::AuthContext (always non-nil; with user=nil when no
  # credentials matched) so downstream code can branch on auth_method
  # without re-parsing the request.
  def authenticate_from_request
    if (header_token = bearer_token).present?
      if (oauth_token = OauthAccessToken.active.find_by(token: header_token))
        # RFC 8707: tokens carry the resource (audience) they were bound
        # to. Reject anything not bound to this MCP server. nil is
        # accepted for backward compat with tokens issued before Block 3
        # (defaulting at /authorize started then; pre-existing tokens
        # have nil and are still valid for THIS resource only).
        return Mcp::AuthContext.anonymous unless resource_acceptable?(oauth_token.resource)
        oauth_token.touch_used!
        return Mcp::AuthContext.oauth(oauth_token)
      end
      if (legacy = User.find_by(api_token: header_token))
        return Mcp::AuthContext.legacy(legacy)
      end
    end

    if (query_token = params[:token].presence) && (legacy = User.find_by(api_token: query_token))
      flag_token_query_deprecation(legacy)
      return Mcp::AuthContext.legacy(legacy)
    end

    Mcp::AuthContext.anonymous
  end

  # `?token=` in the URL leaks into kamal-proxy access logs (the Rails
  # `filter_parameters` redaction only applies to Rails app logs, not the
  # Go reverse-proxy). The Authorization header is the safe equivalent.
  # Mark every query-param-authed response as deprecated so clients
  # migrate, and rate-limited audit so we can see when the last
  # legitimate caller stops using it.
  def flag_token_query_deprecation(user)
    response.set_header("Deprecation", "true")
    response.set_header("Sunset", 6.months.from_now.httpdate)
    response.set_header("Link",
      '</docs>; rel="deprecation", </docs>; rel="sunset"')

    if RateLimit.allow?(key: "mcp-token-query-audit:user:#{user.id}", limit: 1, window: 3600)
      Oauth::Audit.log("legacy_token_query_used",
        user: user,
        request: request,
        metadata: { reminder: "?token= leaks into proxy logs; clients should send Authorization: Bearer instead" })
    end
  end

  def resource_acceptable?(token_resource)
    # RFC 8707: tokens carry the resource (audience) they were bound to.
    # Strict equality — the pre-Block-3 nil grandfather was closed by the
    # 20260507100001 migration + model `validates :resource, presence`.
    token_resource == Oauth::BaseUrl.canonical_resource
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

  # Returns true (and renders the 429) if this user is over budget for
  # the current minute. 60 req/min per authenticated user — across all
  # their tokens (OAuth + legacy), since the bucket key is the user_id.
  def rate_limit_exceeded?(user)
    bucket = McpRateBucket.acquire("user:#{user.id}")
    return false if bucket.allow!

    render(json: {
      jsonrpc: "2.0", id: nil,
      error: { code: -32029, message: "Rate limited: 60 requests/minute per account." }
    }, status: :too_many_requests)
    true
  end
end

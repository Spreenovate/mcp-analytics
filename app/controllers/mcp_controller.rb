class McpController < ApplicationController
  # MCP is a JSON-RPC endpoint. Skip CSRF because clients are programmatic and
  # authenticate with a bearer token or URL token param, not a session cookie.
  skip_before_action :verify_authenticity_token, raise: false, only: [:dispatch_rpc]

  before_action :throttle_if_authenticated, only: [:dispatch_rpc]

  # POST /mcp
  def dispatch_rpc
    user = authenticate_from_request

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
      auth: "Provide API token via 'Authorization: Bearer <token>' header or ?token=<token> query param. Without a token, only signup tools are exposed."
    }
  end

  private

  def authenticate_from_request
    token = bearer_token || params[:token].presence
    return nil if token.blank?

    User.find_by(api_token: token)
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    return nil unless header =~ /\ABearer\s+(.+)\z/i
    Regexp.last_match(1).strip
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

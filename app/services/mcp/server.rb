module Mcp
  # Dispatches JSON-RPC 2.0 requests per the MCP spec.
  # Tools exposed depend on the AuthContext: anonymous callers see signup
  # tools only; authenticated callers see analytics tools filtered by their
  # OAuth scopes (legacy api_token callers are treated as having all scopes).
  class Server
    PROTOCOL_VERSION = "2025-06-18".freeze
    SERVER_INFO = { name: "mcp-analytics", version: "0.1.0" }.freeze

    def initialize(auth: nil, request: nil, user: nil)
      # `user:` kept for tests/callers that still pass a User; treated as
      # legacy auth so the full scope vocabulary is granted.
      @auth = auth || (user ? AuthContext.legacy(user) : nil)

      # The MCP controller 401s unauthenticated requests before reaching
      # the server. Constructing a Server without an authenticated context
      # is a programming error — bail loudly rather than silently fall
      # through to a dispatcher that'd serve every tool to no-one.
      raise ArgumentError, "Mcp::Server requires authenticated AuthContext" if @auth.nil? || !@auth.authenticated?

      @tools = Tools.new(user: @auth.user, request: request)
    end

    def handle(rpc)
      id = rpc["id"]
      method = rpc["method"]
      params = rpc["params"] || {}

      case method
      when "initialize"
        ok(id, initialize_result(params))
      when "notifications/initialized", "notifications/cancelled"
        nil # notifications have no response
      when "tools/list"
        ok(id, { tools: visible_tools_for_wire })
      when "tools/call"
        handle_tool_call(id, params)
      when "ping"
        ok(id, {})
      else
        err(id, -32601, "method not found: #{method}")
      end
    end

    private

    def initialize_result(_params)
      {
        protocolVersion: PROTOCOL_VERSION,
        serverInfo: SERVER_INFO,
        capabilities: { tools: { listChanged: false } },
        instructions: authed_instructions
      }
    end

    # Tools the caller is allowed to see. The controller 401s unauthenticated
    # callers before dispatch, so we always start from AUTHENTICATED here.
    # Further filters:
    #   - oauth_forbidden tools hidden from OAuth-issued tokens
    #   - tools whose required scope is not granted
    def visible_tools
      ToolSchemas::AUTHENTICATED.select { |schema| tool_allowed?(schema) }
    end

    def visible_tools_for_wire
      visible_tools.map { |schema| schema.except(*ToolSchemas::INTERNAL_KEYS) }
    end

    def tool_allowed?(schema)
      return false if @auth.oauth? && schema[ToolSchemas::OAUTH_FORBIDDEN_KEY]

      required = schema[ToolSchemas::SCOPE_KEY]
      return true if required.nil? # tool has no scope requirement
      @auth.granted?(required)
    end

    def handle_tool_call(id, params)
      name = params["name"].to_s
      args = params["arguments"] || {}

      schema = visible_tools.find { |t| t[:name] == name }
      unless schema
        # Distinguish "tool exists but you can't use it" from "no such tool"
        # to give the client an actionable error.
        full_schema = (ToolSchemas::AUTHENTICATED + ToolSchemas::UNAUTHENTICATED).find { |t| t[:name] == name }
        return ok(id, tool_error(reason_for_unavailable(name, full_schema)))
      end

      begin
        result = @tools.public_send(name, args)
        ok(id, tool_success(result))
      rescue ArgumentError => e
        ok(id, tool_error("Invalid arguments: #{e.message}"))
      rescue Tools::NotFoundError => e
        ok(id, tool_error(e.message))
      rescue Tools::RateLimitedError => e
        ok(id, tool_error("Rate limited: #{e.message}"))
      rescue ActiveRecord::RecordInvalid => e
        ok(id, tool_error(e.message))
      rescue StandardError => e
        Rails.logger.error("MCP tool '#{name}' failed: #{e.class}: #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        ok(id, tool_error("Internal error while calling '#{name}'."))
      end
    end

    def reason_for_unavailable(name, schema)
      return "Tool '#{name}' is not available. Call tools/list for the full list." if schema.nil?

      # Note: the controller 401s unauthenticated requests before dispatch,
      # so @auth.authenticated? is always true here.

      if @auth.oauth? && schema[ToolSchemas::OAUTH_FORBIDDEN_KEY]
        return "Tool '#{name}' is not available to OAuth-issued tokens. " \
               "Use the legacy ?token=<api_token> URL if you need to rotate your master API token."
      end

      required = schema[ToolSchemas::SCOPE_KEY]
      if required && !@auth.granted?(required)
        return "Tool '#{name}' requires the '#{required}' scope. " \
               "Re-authorize this connector with that scope to use it."
      end

      "Tool '#{name}' is not available."
    end

    def tool_success(result)
      # MCP spec says structuredContent must be a JSON object. Several of our
      # tools (list_sites, top_pages, timeseries, ...) naturally return arrays —
      # wrap them under an "items" key so strict clients (Anthropic Claude)
      # don't reject the response as "malformed".
      structured = result.is_a?(Array) ? { "items" => result } : result

      {
        content: [ { type: "text", text: JSON.pretty_generate(result) } ],
        structuredContent: structured,
        isError: false
      }
    end

    def tool_error(message)
      { content: [ { type: "text", text: message } ], isError: true }
    end

    def ok(id, result)
      { jsonrpc: "2.0", id: id, result: result }
    end

    def err(id, code, message)
      { jsonrpc: "2.0", id: id, error: { code: code, message: message } }
    end

    def authed_instructions
      "You are connected to mcp-analytics with an authenticated token. " \
      "Use list_sites to discover site_ids, then query with get_overview, " \
      "top_pages, top_referrers, etc. Period defaults to last_7_days. " \
      "If the account has more than one site and the user did not specify " \
      "which one, ASK before querying. Every analytics response includes " \
      "site_id and domain — always echo the domain in your answer so the " \
      "user can confirm you queried the right site."
    end
  end
end

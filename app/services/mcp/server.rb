module Mcp
  # Dispatches JSON-RPC 2.0 requests per the MCP spec.
  # Tools exposed depend on whether the caller is authenticated — the
  # controller passes user: nil for anonymous sessions.
  class Server
    PROTOCOL_VERSION = "2025-06-18".freeze
    SERVER_INFO = { name: "mcp-analytics", version: "0.1.0" }.freeze

    def initialize(user: nil, request: nil)
      @user = user
      @tools = Tools.new(user: user, request: request)
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
        ok(id, { tools: visible_tools })
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
        instructions: @user ? authed_instructions : unauthed_instructions
      }
    end

    def visible_tools
      @user ? ToolSchemas::AUTHENTICATED : ToolSchemas::UNAUTHENTICATED
    end

    def handle_tool_call(id, params)
      name = params["name"].to_s
      args = params["arguments"] || {}

      schema = visible_tools.find { |t| t[:name] == name }
      unless schema
        return ok(id, tool_error("Tool '#{name}' is not available. " \
          "#{@user ? 'Call tools/list for the full list.' : 'Authenticate by providing your API token to unlock analytics tools.'}"))
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

    def unauthed_instructions
      "You are connected to mcp-analytics without authentication. Call " \
      "register_account with the user's email to start signup. After the " \
      "user verifies, they'll update the MCP URL with their token to unlock " \
      "analytics tools."
    end
  end
end

require "test_helper"

class McpControllerTest < ActionDispatch::IntegrationTest
  setup do
    @prev_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @user = User.create!(email: "rpc@example.com", email_verified_at: Time.current)
  end

  teardown do
    Rails.cache = @prev_cache
  end

  # --- info / GET --------------------------------------------------------

  test "GET /mcp returns connector info" do
    get "/mcp"
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "mcp-analytics", body["name"]
    assert_includes body["auth"], "OAuth"
    assert_includes body["auth"], "401"
  end

  # --- JSON-RPC dispatch -------------------------------------------------

  test "initialize without auth returns 401 with WWW-Authenticate" do
    rpc("initialize")
    assert_response :unauthorized
    assert_match %r{Bearer resource_metadata=}, response.headers["WWW-Authenticate"]
    assert_no_match %r{error="invalid_token"}, response.headers["WWW-Authenticate"]
  end

  test "initialize returns protocol version and authed instructions with valid token" do
    rpc("initialize", token: @user.api_token)
    assert_response :success
    result = json_body["result"]
    assert_equal "2025-06-18", result["protocolVersion"]
    assert_includes result["instructions"], "list_sites"
  end

  test "tools/list shows analytics tools with valid token" do
    rpc("tools/list", token: @user.api_token)
    names = json_body["result"]["tools"].map { |t| t["name"] }
    assert_includes names, "list_sites"
    assert_includes names, "get_overview"
    assert_includes names, "get_started_guide"
    assert_not_includes names, "register_account"
  end

  test "ping with valid token returns empty result" do
    rpc("ping", token: @user.api_token)
    assert_equal({}, json_body["result"])
  end

  test "unknown method with valid token returns JSON-RPC error -32601" do
    rpc("does_not_exist", token: @user.api_token)
    assert_equal(-32601, json_body["error"]["code"])
  end

  # --- Auth: token routes --------------------------------------------------

  test "Bearer header is accepted" do
    rpc_call("tools/list", headers: { "Authorization" => "Bearer #{@user.api_token}" })
    names = json_body["result"]["tools"].map { |t| t["name"] }
    assert_includes names, "list_sites"
  end

  test "?token query param is accepted" do
    rpc_call("tools/list", query: { token: @user.api_token })
    names = json_body["result"]["tools"].map { |t| t["name"] }
    assert_includes names, "list_sites"
  end

  test "invalid token returns 401 + WWW-Authenticate with error=invalid_token" do
    rpc_call("tools/list", headers: { "Authorization" => "Bearer mcpa_garbage" })
    assert_response :unauthorized
    assert_match %r{Bearer error="invalid_token"}, response.headers["WWW-Authenticate"]
    assert_match %r{resource_metadata=}, response.headers["WWW-Authenticate"]
  end

  test "no token returns 401 + WWW-Authenticate (triggers OAuth discovery)" do
    rpc_call("tools/list", headers: {})
    assert_response :unauthorized
    assert_match %r{Bearer resource_metadata="[^"]+/\.well-known/oauth-protected-resource"},
                 response.headers["WWW-Authenticate"]
    assert_no_match %r{error="invalid_token"}, response.headers["WWW-Authenticate"]
  end

  test "tools/call without auth returns 401 (no anonymous dispatch)" do
    rpc_call("tools/call",
             params: { "name" => "list_sites", "arguments" => {} },
             headers: {})
    assert_response :unauthorized
    assert_match %r{Bearer resource_metadata=}, response.headers["WWW-Authenticate"]
  end

  test "invalid ?token= query param returns 401 with error=invalid_token" do
    rpc_call("tools/list", query: { token: "mcpa_garbage" })
    assert_response :unauthorized
    assert_match %r{Bearer error="invalid_token"}, response.headers["WWW-Authenticate"]
  end

  # --- tools/call dispatch -------------------------------------------------

  test "calling list_sites with auth returns the user's sites" do
    @user.sites.create!(domain: "example.com", privacy_mode: "strict")
    rpc("tools/call", token: @user.api_token,
        params: { name: "list_sites", arguments: {} })
    result = json_body["result"]
    assert_equal false, result["isError"]
    assert_equal 1, result["structuredContent"].length
  end

  test "ArgumentError from tool is wrapped as tool_error" do
    rpc("tools/call", token: @user.api_token,
        params: { name: "add_site", arguments: { "domain" => "" } })
    result = json_body["result"]
    assert_equal true, result["isError"]
    assert_includes result["content"].first["text"], "Invalid arguments"
  end

  # --- Rate limit ---------------------------------------------------------

  test "authenticated requests above 60/min get rate-limited" do
    60.times { rpc("ping", token: @user.api_token) }
    rpc("ping", token: @user.api_token)
    assert_response :too_many_requests
    assert_equal(-32029, json_body["error"]["code"])
  end

  # --- batch & malformed --------------------------------------------------

  test "batch request returns array of responses" do
    body = [
      { "jsonrpc" => "2.0", "id" => 1, "method" => "ping" },
      { "jsonrpc" => "2.0", "id" => 2, "method" => "ping" }
    ].to_json
    post "/mcp?token=#{@user.api_token}", params: body,
         headers: { "Content-Type" => "application/json" }
    arr = JSON.parse(response.body)
    assert_equal 2, arr.length
    assert_equal [1, 2], arr.map { |r| r["id"] }
  end

  test "empty body with auth returns 400" do
    post "/mcp?token=#{@user.api_token}", params: "",
         headers: { "Content-Type" => "application/json" }
    assert_response :bad_request
  end

  # --- OAuth integration --------------------------------------------------

  test "WWW-Authenticate header points at protected-resource metadata" do
    get "/mcp"
    assert_match %r{Bearer resource_metadata="[^"]+/\.well-known/oauth-protected-resource"},
                 response.headers["WWW-Authenticate"]
  end

  test "valid OAuth access token authenticates and unlocks tools" do
    client = OauthClient.create!(client_name: "X", redirect_uri_list: ["https://x.example/cb"])
    token  = OauthAccessToken.create!(user: @user, oauth_client: client, scope: "analytics:read")

    rpc_call("tools/list", headers: { "Authorization" => "Bearer #{token.token}" })
    assert_response :success
    names = json_body["result"]["tools"].map { |t| t["name"] }
    assert_includes names, "list_sites"
    assert token.reload.last_used_at.present?, "should touch last_used_at"
  end

  # --- Scope enforcement (OAuth tokens) ----------------------------------

  test "OAuth token with only analytics:read hides write tools from tools/list" do
    client = OauthClient.create!(client_name: "X", redirect_uri_list: [ "https://x.example/cb" ])
    token  = OauthAccessToken.create!(user: @user, oauth_client: client, scope: "analytics:read")

    rpc_call("tools/list", headers: { "Authorization" => "Bearer #{token.token}" })
    names = json_body["result"]["tools"].map { |t| t["name"] }
    assert_includes names, "list_sites"
    assert_includes names, "get_overview"
    assert_not_includes names, "add_site"
    assert_not_includes names, "remove_site"
    assert_not_includes names, "regenerate_api_token"
  end

  test "OAuth token with analytics:read+manage exposes write tools but never regenerate_api_token" do
    client = OauthClient.create!(client_name: "X", redirect_uri_list: [ "https://x.example/cb" ])
    token  = OauthAccessToken.create!(user: @user, oauth_client: client,
                                       scope: "analytics:read analytics:manage")

    rpc_call("tools/list", headers: { "Authorization" => "Bearer #{token.token}" })
    names = json_body["result"]["tools"].map { |t| t["name"] }
    assert_includes names, "add_site"
    assert_includes names, "remove_site"
    # Even with full scopes, OAuth-issued tokens can never extract the
    # legacy master api_token through this tool.
    assert_not_includes names, "regenerate_api_token"
  end

  test "OAuth token cannot call regenerate_api_token even when name guessed" do
    client = OauthClient.create!(client_name: "X", redirect_uri_list: [ "https://x.example/cb" ])
    token  = OauthAccessToken.create!(user: @user, oauth_client: client,
                                       scope: "analytics:read analytics:manage")
    original = @user.api_token

    rpc_call("tools/call",
             params: { "name" => "regenerate_api_token", "arguments" => {} },
             headers: { "Authorization" => "Bearer #{token.token}" })
    result = json_body["result"]
    assert_equal true, result["isError"]
    assert_match(/not available to OAuth/, result["content"].first["text"])
    assert_equal original, @user.reload.api_token
  end

  test "OAuth token without analytics:manage scope cannot call add_site" do
    client = OauthClient.create!(client_name: "X", redirect_uri_list: [ "https://x.example/cb" ])
    token  = OauthAccessToken.create!(user: @user, oauth_client: client, scope: "analytics:read")

    rpc_call("tools/call",
             params: { "name" => "add_site", "arguments" => { "domain" => "x.com" } },
             headers: { "Authorization" => "Bearer #{token.token}" })
    result = json_body["result"]
    assert_equal true, result["isError"]
    assert_match(/analytics:manage/, result["content"].first["text"])
    assert_equal 0, @user.sites.count
  end

  test "legacy api_token can call regenerate_api_token" do
    rpc("tools/list", token: @user.api_token)
    names = json_body["result"]["tools"].map { |t| t["name"] }
    assert_includes names, "regenerate_api_token", "legacy callers must still see the rotate tool"
  end

  test "revoked OAuth access token returns 401" do
    client = OauthClient.create!(client_name: "X", redirect_uri_list: [ "https://x.example/cb" ])
    token  = OauthAccessToken.create!(user: @user, oauth_client: client, scope: "analytics:read")
    token.revoke!

    rpc_call("tools/list", headers: { "Authorization" => "Bearer #{token.token}" })
    assert_response :unauthorized
    assert_match %r{Bearer error="invalid_token"}, response.headers["WWW-Authenticate"]
  end

  # --- RFC 8707 resource binding at the gate ------------------------------

  test "OAuth token defaults resource to canonical (no nil grandfather)" do
    client = OauthClient.create!(client_name: "X", redirect_uri_list: [ "https://x.example/cb" ])
    token  = OauthAccessToken.create!(user: @user, oauth_client: client,
                                       scope: "analytics:read")
    assert_equal Oauth::BaseUrl.canonical_resource, token.resource

    # Hard enforcement: DB-level NOT NULL catches anything that bypasses
    # callbacks (e.g. update_column, raw SQL, future code paths).
    assert_raises(ActiveRecord::NotNullViolation) do
      token.update_column(:resource, nil)
    end
  end

  test "OAuth token bound to canonical resource is accepted" do
    client = OauthClient.create!(client_name: "X", redirect_uri_list: [ "https://x.example/cb" ])
    token  = OauthAccessToken.create!(user: @user, oauth_client: client,
                                       scope: "analytics:read",
                                       resource: "#{Oauth::BaseUrl.value}/mcp")

    rpc_call("tools/list", headers: { "Authorization" => "Bearer #{token.token}" })
    assert_response :success
  end

  test "OAuth token bound to a foreign resource is rejected at the MCP gate (RFC 8707)" do
    client = OauthClient.create!(client_name: "X", redirect_uri_list: [ "https://x.example/cb" ])
    token  = OauthAccessToken.create!(user: @user, oauth_client: client,
                                       scope: "analytics:read",
                                       resource: "https://other-mcp.example/mcp")

    rpc_call("tools/list", headers: { "Authorization" => "Bearer #{token.token}" })
    assert_response :unauthorized
    assert_match %r{Bearer error="invalid_token"}, response.headers["WWW-Authenticate"]
  end

  test "expired OAuth access token returns 401" do
    client = OauthClient.create!(client_name: "X", redirect_uri_list: [ "https://x.example/cb" ])
    token  = OauthAccessToken.create!(user: @user, oauth_client: client, scope: "analytics:read",
                                       expires_at: 1.minute.ago)

    rpc_call("tools/list", headers: { "Authorization" => "Bearer #{token.token}" })
    assert_response :unauthorized
    assert_match %r{Bearer error="invalid_token"}, response.headers["WWW-Authenticate"]
  end

  private

  def rpc(method, params: {}, token: nil)
    rpc_call(method, params: params, query: token ? { token: token } : {})
  end

  def rpc_call(method, params: {}, query: {}, headers: {})
    body = { "jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params }.to_json
    url = "/mcp"
    url += "?" + Rack::Utils.build_query(query) unless query.empty?
    post url, params: body, headers: headers.merge("Content-Type" => "application/json")
  end

  def json_body
    JSON.parse(response.body)
  end
end

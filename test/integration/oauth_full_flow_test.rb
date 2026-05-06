require "test_helper"

# End-to-end happy path: client registers -> authorize -> email signup ->
# verify-link click -> consent allow -> exchange code -> /mcp call.
class OauthFullFlowTest < ActionDispatch::IntegrationTest
  setup do
    @prev_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end
  teardown { Rails.cache = @prev_cache }

  test "register -> authorize -> verify -> consent -> token -> /mcp end-to-end" do
    # 1. Dynamic client registration (RFC 7591)
    post "/oauth/register",
         params: { client_name: "ClaudeTest",
                   redirect_uris: ["https://claude.ai/api/oauth/callback"] }.to_json,
         headers: { "Content-Type" => "application/json" }
    assert_response :created
    client_id = JSON.parse(response.body)["client_id"]

    # 2. PKCE
    verifier  = SecureRandom.urlsafe_base64(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)

    # 3. Authorize endpoint -> persists request, renders email form
    get "/oauth/authorize", params: {
      client_id: client_id,
      redirect_uri: "https://claude.ai/api/oauth/callback",
      response_type: "code",
      code_challenge: challenge,
      code_challenge_method: "S256",
      state: "state-abc",
      scope: "analytics:read"
    }
    assert_response :success
    auth_request = OauthAuthorizationRequest.last
    assert_equal client_id, auth_request.oauth_client.client_id

    # 4. Email submitted
    post "/oauth/authorize/start",
         params: { request_token: auth_request.request_token, email: "e2e@example.com" }
    assert_response :success
    verification = EmailVerification.last
    assert_equal auth_request.id, verification.oauth_authorization_request_id

    # 5. Email link clicked -> confirmation form rendered (Block 5)
    get verify_path(token: verification.verify_token)
    assert_response :success
    assert_includes response.body, "ClaudeTest" # client name on confirm page

    # 6. User submits the confirmation form -> redirected to /oauth/consent
    post verify_confirm_path(token: verification.verify_token)
    assert_response :redirect
    consent_url = response.location
    assert_match(%r{/oauth/consent/}, consent_url)
    assert_includes consent_url, "grant="

    # 6. Consent screen renders
    get consent_url
    assert_response :success
    assert_includes response.body, "ClaudeTest"
    assert_includes response.body, "e2e@example.com"

    # 7. Allow -> redirected to client with code
    grant = Rack::Utils.parse_nested_query(URI.parse(consent_url).query)["grant"]
    post "/oauth/consent/#{auth_request.request_token}",
         params: { decision: "allow", grant: grant }
    assert_response :redirect
    callback = URI.parse(response.location)
    assert_equal "claude.ai", callback.host
    qs = Rack::Utils.parse_nested_query(callback.query)
    assert qs["code"].present?
    assert_equal "state-abc", qs["state"]

    # 8. Exchange code for access_token
    post "/oauth/token", params: {
      grant_type: "authorization_code",
      code: qs["code"],
      redirect_uri: "https://claude.ai/api/oauth/callback",
      client_id: client_id,
      code_verifier: verifier
    }
    assert_response :success
    token_data = JSON.parse(response.body)
    access_token = token_data["access_token"]
    assert access_token.start_with?("mcpa_oauth_")

    # 9. Use access_token against /mcp -> tools/list returns analytics tools
    body = { "jsonrpc" => "2.0", "id" => 1, "method" => "tools/list" }.to_json
    post "/mcp", params: body,
         headers: { "Content-Type" => "application/json",
                    "Authorization" => "Bearer #{access_token}" }
    assert_response :success
    names = JSON.parse(response.body)["result"]["tools"].map { |t| t["name"] }
    assert_includes names, "list_sites"
    assert_includes names, "get_overview"
  end
end

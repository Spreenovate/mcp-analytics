require "test_helper"

# Block 5: ensure CSP is actually being sent on real responses. The
# initializer is the source of truth — these tests guard against a
# future change accidentally weakening it.
class ContentSecurityPolicyTest < ActionDispatch::IntegrationTest
  test "homepage emits a CSP header with strict script-src" do
    get root_path
    assert_response :success
    csp = response.headers["Content-Security-Policy"]
    assert csp.present?, "CSP header must be set on rendered pages"
    assert_match(/script-src 'self'(?!\s+'unsafe-inline')/, csp,
      "script-src must NOT include 'unsafe-inline' — that's the whole point")
    assert_match(/object-src 'none'/, csp)
    assert_match(/frame-ancestors 'none'/, csp)
    assert_match(/base-uri 'self'/, csp)
  end

  # Regression: an earlier draft of the CSP set `script-src 'self'`
  # only, which would have blocked the dogfooding tracker
  # (`t.mcp-analytics.com`) in production. The tracker host MUST be
  # allowlisted, and it must come from the same env var the layout
  # reads (TRACKER_BASE_URL) so the two stay in sync.
  test "script-src allowlists the dogfooding tracker host" do
    get root_path
    csp = response.headers["Content-Security-Policy"]
    tracker = ENV.fetch("TRACKER_BASE_URL", "https://t.mcp-analytics.com")
    assert_includes csp, tracker, "CSP must permit the production tracker host"
  end

  test "form-action is locked to :self (no broad :https or dead native schemes)" do
    get root_path
    csp = response.headers["Content-Security-Policy"]
    assert_match(/form-action 'self'(?:;|$)/, csp,
      "form-action should be exactly 'self' — :https was gratuitously broad and the native schemes were inert")
  end

  test "GET /verify (confirmation form) emits CSP and contains zero inline scripts" do
    v = EmailVerification.create!(email: "csp_get@example.com")
    get verify_path(token: v.verify_token)
    assert_response :success
    assert response.headers["Content-Security-Policy"].present?
    inline_scripts = response.body.scan(%r{<script(?![^>]*\bsrc=)[^>]*>}).size
    assert_equal 0, inline_scripts, "no inline <script> blocks allowed under CSP"
  end

  test "POST /verify (verified page) references external mcp_ui.js, no inline scripts" do
    v = EmailVerification.create!(email: "csp_post@example.com")
    post verify_confirm_path(token: v.verify_token)
    assert_response :success
    # External, digested script tag.
    assert_match(%r{<script[^>]*src="/assets/mcp_ui-[^"]*\.js"[^>]*></script>}, response.body)
    inline_scripts = response.body.scan(%r{<script(?![^>]*\bsrc=)[^>]*>}).size
    assert_equal 0, inline_scripts
  end

  test "settings page (signed in) emits CSP and uses external script" do
    sign_in_via_verify("settings_csp@example.com")
    get settings_path
    assert_response :success
    assert response.headers["Content-Security-Policy"].present?
    inline_scripts = response.body.scan(%r{<script(?![^>]*\bsrc=)[^>]*>}).size
    assert_equal 0, inline_scripts
  end

  test "consent screen emits CSP" do
    client = OauthClient.create!(client_name: "ClaudeCSP",
                                  redirect_uri_list: [ "https://claude.ai/cb" ])
    verifier  = SecureRandom.urlsafe_base64(32)
    challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false)
    auth_request = OauthAuthorizationRequest.create!(
      oauth_client: client, redirect_uri: "https://claude.ai/cb",
      code_challenge: challenge, code_challenge_method: "S256",
      scope: "analytics:read"
    )
    user = User.create!(email: "consent_csp@example.com", email_verified_at: Time.current)
    auth_request.update!(user: user)
    grant = Oauth::AuthorizationsController.mint_grant(auth_request, user)

    get oauth_consent_path(request_token: auth_request.request_token, grant: grant)
    assert_response :success
    assert response.headers["Content-Security-Policy"].present?
  end
end

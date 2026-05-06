require "test_helper"

class VerificationsControllerTest < ActionDispatch::IntegrationTest
  # --- GET /verify/:token (read-only confirmation page) ------------------

  test "GET /verify/:token does NOT create a user or mark the verification used" do
    v = EmailVerification.create!(email: "ro@example.com")

    assert_no_difference -> { User.count } do
      get verify_path(token: v.verify_token)
    end
    assert_response :success
    assert_includes response.body, "Sign me in"
    assert_nil v.reload.used_at, "GET must be a no-op state-wise (defends against <img src=> CSRF)"
  end

  test "GET /verify/:token with OAuth context advertises the client name" do
    client = OauthClient.create!(client_name: "ClaudeForReview",
                                  redirect_uri_list: [ "https://claude.ai/cb" ])
    auth_request = OauthAuthorizationRequest.create!(
      oauth_client: client, redirect_uri: "https://claude.ai/cb",
      code_challenge: "x", code_challenge_method: "S256",
      scope: "analytics:read"
    )
    v = EmailVerification.create!(email: "oauth_get@example.com",
                                   oauth_authorization_request: auth_request)

    get verify_path(token: v.verify_token)
    assert_response :success
    assert_includes response.body, "ClaudeForReview"
  end

  test "expired token renders :expired with 410 on GET" do
    v = EmailVerification.create!(email: "expired@example.com", expires_at: 1.hour.ago)
    get verify_path(token: v.verify_token)
    assert_response :gone
  end

  test "unknown token renders :expired with 410 on GET" do
    get verify_path(token: "totally-fake-token")
    assert_response :gone
  end

  test "GET /verify sets Referrer-Policy: no-referrer + Cache-Control: no-store" do
    v = EmailVerification.create!(email: "referrer@example.com")
    get verify_path(token: v.verify_token)
    assert_response :success
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "no-store",    response.headers["Cache-Control"]
  end

  # --- POST /verify/:token (does the work) ------------------------------

  test "POST /verify/:token creates user, marks verification used, shows token" do
    v = EmailVerification.create!(email: "verify@example.com")

    assert_difference -> { User.count }, 1 do
      post verify_confirm_path(token: v.verify_token)
    end
    assert_response :success

    user = User.find_by(email: "verify@example.com")
    assert user.email_verified?
    assert_includes response.body, user.api_token
    assert v.reload.used_at.present?
  end

  test "POST with expired token renders 410" do
    v = EmailVerification.create!(email: "expired_post@example.com", expires_at: 1.hour.ago)
    post verify_confirm_path(token: v.verify_token)
    assert_response :gone
  end

  test "POST with unknown token renders 410" do
    post verify_confirm_path(token: "totally-fake-token")
    assert_response :gone
  end

  test "second POST on the same link is 410 (single-use)" do
    v = EmailVerification.create!(email: "twice@example.com")
    post verify_confirm_path(token: v.verify_token)

    assert_no_difference -> { User.count } do
      post verify_confirm_path(token: v.verify_token)
    end
    assert_response :gone
  end

  # --- OAuth-flow integration --------------------------------------------

  test "POST verify with OAuth context redirects to /oauth/consent with grant" do
    client = OauthClient.create!(client_name: "TestApp",
                                  redirect_uri_list: [ "https://app.example/cb" ])
    auth_request = OauthAuthorizationRequest.create!(
      oauth_client: client, redirect_uri: "https://app.example/cb",
      code_challenge: "x", code_challenge_method: "S256",
      scope: "analytics:read"
    )
    v = EmailVerification.create!(email: "oauth@example.com",
                                   oauth_authorization_request: auth_request)

    assert_difference -> { User.count }, 1 do
      post verify_confirm_path(token: v.verify_token)
    end
    assert_response :redirect
    assert_match(%r{/oauth/consent/}, response.location)
    assert_includes response.location, "grant="

    user = User.find_by(email: "oauth@example.com")
    assert_equal user.id, auth_request.reload.user_id
  end

  test "POST verify with OAuth context for existing user reuses the user" do
    existing = User.create!(email: "existing@example.com", email_verified_at: Time.current)
    client = OauthClient.create!(client_name: "TestApp",
                                  redirect_uri_list: [ "https://app.example/cb" ])
    auth_request = OauthAuthorizationRequest.create!(
      oauth_client: client, redirect_uri: "https://app.example/cb",
      code_challenge: "x", code_challenge_method: "S256",
      scope: "analytics:read"
    )
    v = EmailVerification.create!(email: "existing@example.com",
                                   oauth_authorization_request: auth_request)

    assert_no_difference -> { User.count } do
      post verify_confirm_path(token: v.verify_token)
    end
    assert_response :redirect
    assert_equal existing.id, auth_request.reload.user_id
  end

  test "expired OAuth auth_request renders :expired on POST (no fallthrough to settings session)" do
    client = OauthClient.create!(client_name: "TestApp",
                                  redirect_uri_list: [ "https://app.example/cb" ])
    auth_request = OauthAuthorizationRequest.create!(
      oauth_client: client, redirect_uri: "https://app.example/cb",
      code_challenge: "x", code_challenge_method: "S256",
      scope: "analytics:read", expires_at: 1.minute.ago
    )
    v = EmailVerification.create!(email: "expired_oauth@example.com",
                                   oauth_authorization_request: auth_request)

    post verify_confirm_path(token: v.verify_token)
    assert_response :gone

    # Critical: must NOT have established a settings session as fallback.
    get settings_path
    assert_redirected_to root_path,
      "expired OAuth verify must not silently sign the user into Settings"
  end

  test "POST verify page sets Referrer-Policy: no-referrer + Cache-Control: no-store" do
    v = EmailVerification.create!(email: "referrer_post@example.com")
    post verify_confirm_path(token: v.verify_token)
    assert_response :success
    assert_equal "no-referrer", response.headers["Referrer-Policy"]
    assert_equal "no-store",    response.headers["Cache-Control"]
  end
end

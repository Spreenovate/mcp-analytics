require "test_helper"

class SettingsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "settings@example.com", email_verified_at: Time.current)
    @client = OauthClient.create!(client_name: "Claude",
                                   redirect_uri_list: [ "https://claude.ai/cb" ])
    @token = OauthAccessToken.create!(user: @user, oauth_client: @client,
                                       scope: "analytics:read analytics:manage")
  end

  # --- Auth gate ----------------------------------------------------------

  test "GET /settings without a session redirects to root with alert" do
    get settings_path
    assert_redirected_to root_path
    assert_match(/sign-in link/, flash[:alert])
  end

  test "POST /settings/connectors/:id/revoke without a session redirects" do
    post revoke_connector_path(id: @token.id)
    assert_redirected_to root_path
    assert_nil @token.reload.revoked_at, "must not revoke without auth"
  end

  # --- Verify-flow integration --------------------------------------------

  test "verifying establishes a settings session" do
    v = EmailVerification.create!(email: "verify-then-settings@example.com")
    get verify_path(token: v.verify_token)
    assert_response :success

    # session was set; now /settings should work
    get settings_path
    assert_response :success
    assert_includes response.body, "verify-then-settings@example.com"
  end

  test "OAuth-flow verify does NOT establish a settings session (different intent)" do
    auth_request = OauthAuthorizationRequest.create!(
      oauth_client: @client, redirect_uri: "https://claude.ai/cb",
      code_challenge: "x", code_challenge_method: "S256",
      scope: "analytics:read"
    )
    v = EmailVerification.create!(email: "oauth@example.com",
                                   oauth_authorization_request: auth_request)
    get verify_path(token: v.verify_token)
    assert_response :redirect # → /oauth/consent

    get settings_path
    assert_redirected_to root_path,
      "OAuth flow shouldn't bleed into a settings session — separate intent"
  end

  # --- Sign-in / signed-in flows ------------------------------------------
  # `sign_in_via_verify` is provided by SettingsSessionHelper.

  test "GET /settings with session shows email + connector list" do
    sign_in_via_verify(@user.email)
    get settings_path
    assert_response :success
    assert_includes response.body, @user.email
    assert_includes response.body, "Claude" # the connector
    assert_includes response.body, "Disconnect"
  end

  test "GET /settings shows empty-state when no connectors" do
    sign_in_via_verify("noconnectors@example.com")
    get settings_path
    assert_response :success
    assert_includes response.body, "No active OAuth connectors"
  end

  test "GET /settings hides revoked + expired tokens" do
    sign_in_via_verify(@user.email)
    @token.revoke!
    OauthAccessToken.create!(user: @user, oauth_client: @client,
                              scope: "analytics:read",
                              expires_at: 1.minute.ago)
    get settings_path
    assert_response :success
    # No connector-row markup anywhere on the page (the empty-state copy
    # itself mentions the word "Disconnect", so match the actual button).
    assert_no_match %r{class="btn danger"}, response.body
    assert_no_match %r{class="connector"}, response.body
    assert_includes response.body, "No active OAuth connectors"
  end

  # --- Revoke -------------------------------------------------------------

  test "revoke disconnects the connector + emits audit event + flashes notice" do
    sign_in_via_verify(@user.email)
    assert_difference -> { OauthAuditEvent.where(event: "token_revoked").count }, 1 do
      post revoke_connector_path(id: @token.id)
    end
    assert_redirected_to settings_path
    assert_match(/Disconnected Claude/, flash[:notice])
    assert @token.reload.revoked_at.present?

    audit = OauthAuditEvent.where(event: "token_revoked").last
    assert_equal "revoked_by_user", audit.metadata_hash["outcome"]
    assert_equal "settings_ui", audit.metadata_hash["source"]
  end

  test "revoking another user's token returns not-found, not 403 (don't leak)" do
    other_user = User.create!(email: "other@example.com", email_verified_at: Time.current)
    other_token = OauthAccessToken.create!(user: other_user, oauth_client: @client,
                                            scope: "analytics:read")
    sign_in_via_verify(@user.email)

    post revoke_connector_path(id: other_token.id)
    assert_redirected_to settings_path
    assert_match(/not found/i, flash[:alert])
    assert_nil other_token.reload.revoked_at
  end

  test "double-revoke is idempotent (no double audit + accurate flash)" do
    sign_in_via_verify(@user.email)
    @token.revoke!

    assert_no_difference -> { OauthAuditEvent.where(event: "token_revoked").count } do
      post revoke_connector_path(id: @token.id)
    end
    assert_redirected_to settings_path
    assert_match(/already disconnected/i, flash[:notice])
  end

  # --- Sign-out + session lifecycle ---------------------------------------

  test "sign_out clears the session" do
    sign_in_via_verify(@user.email)
    post settings_sign_out_path
    assert_redirected_to root_path

    get settings_path
    assert_redirected_to root_path # session is gone
  end

  test "session expires after 30min idle" do
    sign_in_via_verify(@user.email)
    travel 31.minutes do
      get settings_path
      assert_redirected_to root_path
    end
  end

  test "active session is sliding — fresh requests reset the idle timer" do
    sign_in_via_verify(@user.email)
    travel 20.minutes do
      get settings_path
      assert_response :success
    end
    travel 39.minutes do
      get settings_path
      assert_response :success # 20+19 < 30 since last seen
    end
  end

  test "session for a deleted user is forgotten" do
    sign_in_via_verify(@user.email)
    @user.destroy!
    get settings_path
    assert_redirected_to root_path
  end

  test "session_version mismatch invalidates the cookie (defeats sign-out replay)" do
    sign_in_via_verify(@user.email)
    # Pre-condition: signed in.
    get settings_path
    assert_response :success

    # Simulate sign-out happening via a different tab (or attacker
    # capturing the cookie before the user signs out): bump the version
    # without resetting our test session. Replayed cookie now mismatches.
    @user.bump_session_version!
    get settings_path
    assert_redirected_to root_path
  end

  test "sign_out bumps session_version (kills cookie value-replay)" do
    sign_in_via_verify(@user.email)
    original_version = @user.reload.session_version

    post settings_sign_out_path
    assert_operator @user.reload.session_version, :>, original_version,
                    "sign_out must bump session_version so replayed cookies mismatch"
  end
end

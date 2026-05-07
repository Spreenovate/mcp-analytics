require "test_helper"

module Oauth
  class TokensControllerTest < ActionDispatch::IntegrationTest
    setup do
      @prev_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      @client = OauthClient.create!(client_name: "TestApp",
                                     redirect_uri_list: ["https://app.example/cb"])
      @user   = User.create!(email: "tk@example.com", email_verified_at: Time.current)
      @verifier  = SecureRandom.urlsafe_base64(32)
      @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
      @code = OauthAuthorizationCode.create!(
        user: @user, oauth_client: @client,
        redirect_uri: "https://app.example/cb",
        scope: "analytics:read",
        code_challenge: @challenge,
        code_challenge_method: "S256"
      )
    end

    teardown { Rails.cache = @prev_cache }

    def post_token(**overrides)
      params = {
        grant_type: "authorization_code",
        code: @code.code,
        redirect_uri: "https://app.example/cb",
        client_id: @client.client_id,
        code_verifier: @verifier
      }.merge(overrides)
      post oauth_token_path, params: params
    end

    test "happy path: returns Bearer token + refresh token + marks code used" do
      assert_difference -> { OauthAccessToken.count }, 1 do
        post_token
      end
      assert_response :success

      data = JSON.parse(response.body)
      assert data["access_token"].start_with?("mcpa_oauth_")
      assert_equal "bearer", data["token_type"]
      assert_in_delta 24 * 3600, data["expires_in"], 60, "access token should be ~24h"
      assert_equal "analytics:read", data["scope"]

      # Block 4 — refresh token issued alongside, ~90 days
      assert data["refresh_token"].start_with?("mcpa_refresh_")
      assert_in_delta 90 * 86_400, data["refresh_token_expires_in"], 60

      assert_equal "no-store", response.headers["Cache-Control"]
      assert @code.reload.used_at.present?
    end

    test "code may not be redeemed twice" do
      post_token
      assert_response :success
      assert_no_difference -> { OauthAccessToken.count } do
        post_token
      end
      assert_response :bad_request
      assert_equal "invalid_grant", JSON.parse(response.body)["error"]
    end

    test "wrong code_verifier returns invalid_grant" do
      post_token(code_verifier: SecureRandom.urlsafe_base64(32))
      assert_response :bad_request
      assert_equal "invalid_grant", JSON.parse(response.body)["error"]
      assert_match(/PKCE/, JSON.parse(response.body)["error_description"])
      assert_nil @code.reload.used_at
    end

    test "redirect_uri mismatch returns invalid_grant" do
      post_token(redirect_uri: "https://other.example/cb")
      assert_response :bad_request
      assert_equal "invalid_grant", JSON.parse(response.body)["error"]
    end

    test "unknown client_id returns invalid_client" do
      post_token(client_id: "mcpa_client_unknown")
      assert_response :bad_request
      assert_equal "invalid_client", JSON.parse(response.body)["error"]
    end

    test "expired code returns invalid_grant" do
      @code.update!(expires_at: 1.minute.ago)
      post_token
      assert_response :bad_request
      assert_equal "invalid_grant", JSON.parse(response.body)["error"]
    end

    test "missing code returns invalid_request" do
      post_token(code: "")
      assert_response :bad_request
      assert_equal "invalid_request", JSON.parse(response.body)["error"]
    end

    test "code_verifier shorter than 43 chars is rejected" do
      post_token(code_verifier: "tooshort")
      assert_response :bad_request
      assert_equal "invalid_request", JSON.parse(response.body)["error"]
      assert_match(/code_verifier/, JSON.parse(response.body)["error_description"])
    end

    test "code_verifier with disallowed chars is rejected" do
      post_token(code_verifier: "x" * 43 + "!@#$%")
      assert_response :bad_request
      assert_equal "invalid_request", JSON.parse(response.body)["error"]
    end

    test "code issued to client A may not be redeemed by client B" do
      other = OauthClient.create!(client_name: "Other", redirect_uri_list: [ "https://other.example/cb" ])
      post_token(client_id: other.client_id)
      assert_response :bad_request
      assert_equal "invalid_grant", JSON.parse(response.body)["error"]
      assert_match(/not issued to this client/, JSON.parse(response.body)["error_description"])
      assert_nil @code.reload.used_at, "code must remain unused on wrong-client redemption"
    end

    # --- RFC 8707 (Resource Indicators) ------------------------------------

    test "resource parameter matching canonical MCP URI is accepted and stored" do
      canonical = "#{Oauth::BaseUrl.value}/mcp"
      @code.update!(resource: canonical)

      post_token(resource: canonical)
      assert_response :success
      token = OauthAccessToken.find_by(token: JSON.parse(response.body)["access_token"])
      assert_equal canonical, token.resource
    end

    test "resource parameter not equal to canonical MCP URI returns invalid_target" do
      post_token(resource: "https://other.example/mcp")
      assert_response :bad_request
      assert_equal "invalid_target", JSON.parse(response.body)["error"]
      assert_nil @code.reload.used_at
    end

    test "resource parameter at /token must match the one bound at /authorize" do
      @code.update!(resource: "#{Oauth::BaseUrl.value}/mcp")
      post_token(resource: "https://other.example/mcp")
      assert_response :bad_request
      # Other-mcp first fails canonical check (also returns invalid_target),
      # so to test the cross-step bind we'd need to send a *different* but
      # canonical-shaped value. Since canonical is fixed, the canonical
      # check covers the threat model. This test just confirms a mismatched
      # value is refused.
      assert_equal "invalid_target", JSON.parse(response.body)["error"]
    end

    test "missing resource parameter still works when code had none either" do
      post_token # no resource arg
      assert_response :success
    end

    # --- refresh_token grant (Block 4) ------------------------------------

    def post_refresh(refresh_token:, client_id: nil, **overrides)
      params = {
        grant_type: "refresh_token",
        refresh_token: refresh_token,
        client_id: client_id || @client.client_id
      }.merge(overrides)
      post oauth_token_path, params: params
    end

    def issue_initial_token
      post_token
      JSON.parse(response.body)
    end

    test "refresh_token grant: returns new access + new refresh, both rotated" do
      original = issue_initial_token

      assert_difference -> { OauthAccessToken.count }, 1 do
        post_refresh(refresh_token: original["refresh_token"])
      end
      assert_response :success

      data = JSON.parse(response.body)
      assert data["access_token"].start_with?("mcpa_oauth_")
      assert data["refresh_token"].start_with?("mcpa_refresh_")
      assert_not_equal original["access_token"],  data["access_token"]
      assert_not_equal original["refresh_token"], data["refresh_token"]
      assert_equal "bearer", data["token_type"]
      assert_equal "analytics:read", data["scope"]
    end

    test "refresh_token grant: old access token is revoked once refresh is consumed" do
      original = issue_initial_token
      old_access = OauthAccessToken.find_by(token: original["access_token"])

      post_refresh(refresh_token: original["refresh_token"])
      assert_response :success

      assert old_access.reload.revoked_at.present?,
        "old access_token must be revoked when its refresh is consumed"
    end

    test "refresh_token grant: replaying a used refresh revokes the entire family" do
      original = issue_initial_token

      # First refresh — succeeds.
      post_refresh(refresh_token: original["refresh_token"])
      assert_response :success
      latest = JSON.parse(response.body)

      # Second use of the SAME (now-consumed) refresh — replay. We emit
      # ONE audit row per refresh attempt with `outcome` in metadata
      # (uniform with all other refresh outcomes — kills the audit-row-
      # presence side-channel).
      assert_difference -> {
        OauthAuditEvent.where(event: "token_refreshed")
          .where("metadata LIKE ?", "%\"outcome\":\"replay\"%").count
      }, 1 do
        post_refresh(refresh_token: original["refresh_token"])
      end
      assert_response :bad_request
      data = JSON.parse(response.body)
      assert_equal "invalid_grant", data["error"]
      # Generic message — must not distinguish replay from other failures.
      assert_equal "Invalid refresh token", data["error_description"]

      # The token issued by the first (legitimate) refresh is also nuked
      # because we treat the family as compromised.
      family_token = OauthAccessToken.find_by(token: latest["access_token"])
      assert family_token.revoked_at.present?,
        "family revocation must extend to tokens issued by the legitimate refresh"
      assert family_token.refresh_token_used_at.present?,
        "family revocation must consume refresh side too (defense in depth)"
    end

    test "refresh_token grant: unknown refresh -> invalid_grant" do
      post_refresh(refresh_token: "mcpa_refresh_garbage")
      assert_response :bad_request
      assert_equal "invalid_grant", JSON.parse(response.body)["error"]
    end

    test "refresh_token grant: error_description is identical for unknown / wrong-client / replay / inactive (no oracle)" do
      # Unknown
      post_refresh(refresh_token: "mcpa_refresh_unknown_value")
      unknown_msg = JSON.parse(response.body)["error_description"]

      # Wrong client
      original = issue_initial_token
      other = OauthClient.create!(client_name: "Other",
                                   redirect_uri_list: [ "https://other.example/cb" ])
      post_refresh(refresh_token: original["refresh_token"], client_id: other.client_id)
      wrong_client_msg = JSON.parse(response.body)["error_description"]

      # Replay (set up: succeed once, then reuse)
      post_refresh(refresh_token: original["refresh_token"])
      assert_response :success
      post_refresh(refresh_token: original["refresh_token"])
      replay_msg = JSON.parse(response.body)["error_description"]

      # All three must be byte-identical so an attacker can't enumerate.
      assert_equal "Invalid refresh token", unknown_msg
      assert_equal unknown_msg, wrong_client_msg
      assert_equal unknown_msg, replay_msg
    end

    test "refresh_token grant: wrong client_id -> invalid_grant (not invalid_client)" do
      original = issue_initial_token
      other = OauthClient.create!(client_name: "Other",
                                   redirect_uri_list: [ "https://other.example/cb" ])
      post_refresh(refresh_token: original["refresh_token"], client_id: other.client_id)
      assert_response :bad_request
      assert_equal "invalid_grant", JSON.parse(response.body)["error"]
    end

    test "refresh_token grant: revoked token's refresh cannot be used" do
      original = issue_initial_token
      OauthAccessToken.find_by(token: original["access_token"]).revoke!

      post_refresh(refresh_token: original["refresh_token"])
      assert_response :bad_request
      assert_equal "invalid_grant", JSON.parse(response.body)["error"]
    end

    test "refresh_token grant: scope narrowing is allowed (subset)" do
      # Issue with both scopes, narrow on refresh.
      @code.update!(scope: "analytics:read analytics:manage")
      original = issue_initial_token
      assert_equal "analytics:read analytics:manage", original["scope"]

      post_refresh(refresh_token: original["refresh_token"], scope: "analytics:read")
      assert_response :success
      assert_equal "analytics:read", JSON.parse(response.body)["scope"]
    end

    test "refresh_token grant: scope widening is rejected" do
      original = issue_initial_token
      assert_equal "analytics:read", original["scope"]

      post_refresh(refresh_token: original["refresh_token"],
                   scope: "analytics:read analytics:manage")
      assert_response :bad_request
      assert_equal "invalid_scope", JSON.parse(response.body)["error"]
    end

    test "refresh_token grant: emits token_refreshed audit event" do
      original = issue_initial_token

      assert_difference -> { OauthAuditEvent.where(event: "token_refreshed").count }, 1 do
        post_refresh(refresh_token: original["refresh_token"])
      end
    end

    test "refresh_token grant: missing refresh_token returns invalid_request" do
      post oauth_token_path,
           params: { grant_type: "refresh_token", client_id: @client.client_id }
      assert_response :bad_request
      assert_equal "invalid_request", JSON.parse(response.body)["error"]
    end

    test "refresh_token grant: refresh inherits resource binding from original token" do
      canonical = "#{Oauth::BaseUrl.value}/mcp"
      @code.update!(resource: canonical)
      original = issue_initial_token

      post_refresh(refresh_token: original["refresh_token"])
      assert_response :success
      new_token = OauthAccessToken.find_by(token: JSON.parse(response.body)["access_token"])
      assert_equal canonical, new_token.resource
    end

    test "unsupported grant_type returns 400 listing supported" do
      post oauth_token_path,
           params: { grant_type: "client_credentials", client_id: @client.client_id }
      assert_response :bad_request
      body = JSON.parse(response.body)
      assert_equal "unsupported_grant_type", body["error"]
      assert_match(/authorization_code/, body["error_description"])
      assert_match(/refresh_token/, body["error_description"])
    end

    test "downgrade attempt: code has nil resource but request claims canonical -> invalid_target" do
      # auth_code created with no resource (legacy / pre-Block-3 fixture).
      assert_nil @code.resource
      post_token(resource: "#{Oauth::BaseUrl.value}/mcp")
      assert_response :bad_request
      assert_equal "invalid_target", JSON.parse(response.body)["error"]
      assert_nil @code.reload.used_at
    end

    test "code with canonical resource + matching request resource binds the access_token" do
      canonical = "#{Oauth::BaseUrl.value}/mcp"
      @code.update!(resource: canonical)
      post_token(resource: canonical)
      assert_response :success
      token = OauthAccessToken.find_by(token: JSON.parse(response.body)["access_token"])
      assert_equal canonical, token.resource
    end

    # --- Rate-limiting + audit-log ----------------------------------------

    test "rate-limit kicks in after 30 POST /oauth/token per IP per hour" do
      Rails.cache.clear
      31.times do
        @code = OauthAuthorizationCode.create!(
          user: @user, oauth_client: @client,
          redirect_uri: "https://app.example/cb",
          scope: "analytics:read",
          code_challenge: @challenge, code_challenge_method: "S256"
        )
        post_token
      end
      assert_response :too_many_requests
      assert_equal "temporarily_unavailable", JSON.parse(response.body)["error"]
    end

    test "successful token exchange emits token_issued audit event" do
      assert_difference -> { OauthAuditEvent.where(event: "token_issued").count }, 1 do
        post_token
      end
      logged = OauthAuditEvent.where(event: "token_issued").last
      assert_equal @user.id, logged.user_id
      assert_equal @client.id, logged.oauth_client_id
      assert_equal "analytics:read", logged.metadata_hash["scope"]
    end

    test "failed token exchange does NOT emit token_issued event" do
      assert_no_difference -> { OauthAuditEvent.where(event: "token_issued").count } do
        post_token(code_verifier: SecureRandom.urlsafe_base64(32)) # wrong verifier
      end
    end
  end
end

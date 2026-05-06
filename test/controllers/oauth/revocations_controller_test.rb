require "test_helper"

module Oauth
  class RevocationsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @prev_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      @client = OauthClient.create!(client_name: "TestApp",
                                     redirect_uri_list: [ "https://app.example/cb" ])
      @user = User.create!(email: "rev@example.com", email_verified_at: Time.current)
      @token = OauthAccessToken.create!(user: @user, oauth_client: @client,
                                         scope: "analytics:read")
    end

    teardown { Rails.cache = @prev_cache }

    test "happy path: revokes the access token + emits audit event" do
      assert_difference -> { OauthAuditEvent.where(event: "token_revoked").count }, 1 do
        post oauth_revoke_path,
             params: { token: @token.token, client_id: @client.client_id }
      end
      assert_response :ok
      assert @token.reload.revoked_at.present?
      assert_not @token.active?
    end

    test "revoking an unknown token returns 200 (don't leak token existence)" do
      post oauth_revoke_path,
           params: { token: "mcpa_oauth_does_not_exist", client_id: @client.client_id }
      assert_response :ok
    end

    test "every revocation call emits exactly one audit event regardless of outcome (no timing oracle)" do
      # success
      assert_difference -> { OauthAuditEvent.where(event: "token_revoked").count }, 1 do
        post oauth_revoke_path, params: { token: @token.token, client_id: @client.client_id }
      end
      assert_equal "revoked", OauthAuditEvent.where(event: "token_revoked").last.metadata_hash["outcome"]

      # already-revoked
      assert_difference -> { OauthAuditEvent.where(event: "token_revoked").count }, 1 do
        post oauth_revoke_path, params: { token: @token.token, client_id: @client.client_id }
      end
      assert_equal "already_revoked", OauthAuditEvent.where(event: "token_revoked").last.metadata_hash["outcome"]

      # unknown token
      assert_difference -> { OauthAuditEvent.where(event: "token_revoked").count }, 1 do
        post oauth_revoke_path, params: { token: "mcpa_oauth_nope", client_id: @client.client_id }
      end
      assert_equal "unknown_token", OauthAuditEvent.where(event: "token_revoked").last.metadata_hash["outcome"]
    end

    test "client_id is REQUIRED (Block 4 hardening — closes unauthenticated revoke)" do
      # RFC 7009 §2.1 marks client_id optional for public clients, but
      # without it any party with a leaked token value could DoS the
      # user's connector. Refresh tokens have a 90-day window, so the
      # gap matters. We require client_id.
      post oauth_revoke_path, params: { token: @token.token }
      assert_response :bad_request
      assert_equal "invalid_request", JSON.parse(response.body)["error"]
      assert_nil @token.reload.revoked_at, "must not revoke without client_id"
    end

    test "revoking a token issued to a different client is a no-op (silent)" do
      other = OauthClient.create!(client_name: "Other",
                                   redirect_uri_list: [ "https://other.example/cb" ])

      post oauth_revoke_path,
           params: { token: @token.token, client_id: other.client_id }
      assert_response :ok
      assert_nil @token.reload.revoked_at,
                 "must not revoke when caller is not the owning client"
    end

    test "missing token returns 400 invalid_request" do
      post oauth_revoke_path, params: { client_id: @client.client_id }
      assert_response :bad_request
      assert_equal "invalid_request", JSON.parse(response.body)["error"]
    end

    test "second revocation of the same token is idempotent (200, audit row marked already_revoked)" do
      post oauth_revoke_path,
           params: { token: @token.token, client_id: @client.client_id }
      assert_response :ok

      # The redesigned audit logs every call (timing-equalised). The
      # second call still 200s and adds an audit row tagged 'already_revoked'.
      assert_difference -> { OauthAuditEvent.where(event: "token_revoked").count }, 1 do
        post oauth_revoke_path,
             params: { token: @token.token, client_id: @client.client_id }
      end
      assert_equal "already_revoked",
                   OauthAuditEvent.where(event: "token_revoked").last.metadata_hash["outcome"]
      assert_response :ok
    end

    test "rate-limited after 30 attempts/hour" do
      31.times do
        post oauth_revoke_path,
             params: { token: "mcpa_oauth_x", client_id: @client.client_id }
      end
      assert_response :too_many_requests
    end

    test "revoking via the refresh_token value also kills the access_token" do
      assert @token.refresh_token.present?, "Block 4 tokens have a refresh_token"

      post oauth_revoke_path,
           params: { token: @token.refresh_token,
                      client_id: @client.client_id,
                      token_type_hint: "refresh_token" }
      assert_response :ok
      @token.reload
      assert @token.revoked_at.present?,         "row revoked"
      assert @token.refresh_token_used_at.present?, "refresh consumed so it can't be redeemed"
    end

    test "revoking via the access_token value also kills the refresh side" do
      post oauth_revoke_path,
           params: { token: @token.token, client_id: @client.client_id }
      assert_response :ok
      @token.reload
      assert @token.revoked_at.present?
      assert @token.refresh_token_used_at.present?
    end

    test "revoked token can no longer authenticate to /mcp" do
      post oauth_revoke_path,
           params: { token: @token.token, client_id: @client.client_id }
      body = { "jsonrpc" => "2.0", "id" => 1, "method" => "tools/list" }.to_json
      post "/mcp", params: body,
           headers: { "Content-Type" => "application/json",
                       "Authorization" => "Bearer #{@token.token}" }
      assert_response :unauthorized
    end

    test "Cache-Control: no-store on success and on errors" do
      post oauth_revoke_path,
           params: { token: @token.token, client_id: @client.client_id }
      assert_equal "no-store", response.headers["Cache-Control"]

      post oauth_revoke_path, params: {}
      assert_equal "no-store", response.headers["Cache-Control"]
    end
  end
end

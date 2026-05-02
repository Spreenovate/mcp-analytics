require "test_helper"

module Oauth
  class AuthorizationsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @prev_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new
      @client = OauthClient.create!(
        client_name: "TestApp",
        redirect_uri_list: ["https://app.example/cb"]
      )
      @verifier  = SecureRandom.urlsafe_base64(32)
      @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
    end

    teardown { Rails.cache = @prev_cache }

    def authorize_params(**overrides)
      {
        client_id: @client.client_id,
        redirect_uri: "https://app.example/cb",
        response_type: "code",
        code_challenge: @challenge,
        code_challenge_method: "S256",
        state: "csrf-token-xyz",
        scope: "read:analytics"
      }.merge(overrides)
    end

    # --- GET /oauth/authorize ----------------------------------------------

    test "GET /oauth/authorize with valid params persists request and renders email form" do
      assert_difference -> { OauthAuthorizationRequest.count }, 1 do
        get oauth_authorize_path, params: authorize_params
      end
      assert_response :success
      assert_includes response.body, "TestApp"
      assert_includes response.body, "Send verification link"
    end

    test "GET /oauth/authorize with unknown client_id renders 400" do
      get oauth_authorize_path, params: authorize_params(client_id: "mcpa_client_unknown")
      assert_response :bad_request
      assert_includes response.body, "invalid_client"
    end

    test "GET /oauth/authorize with mismatched redirect_uri renders 400" do
      get oauth_authorize_path, params: authorize_params(redirect_uri: "https://evil.example/cb")
      assert_response :bad_request
      assert_includes response.body, "invalid_redirect_uri"
    end

    test "GET /oauth/authorize with response_type=token redirects with error" do
      get oauth_authorize_path, params: authorize_params(response_type: "token")
      assert_response :redirect
      uri = URI.parse(response.location)
      query = Rack::Utils.parse_nested_query(uri.query)
      assert_equal "unsupported_response_type", query["error"]
      assert_equal "csrf-token-xyz", query["state"]
    end

    test "GET /oauth/authorize without code_challenge redirects with error" do
      get oauth_authorize_path, params: authorize_params(code_challenge: "")
      assert_response :redirect
      assert_match(/error=invalid_request/, response.location)
    end

    test "GET /oauth/authorize with code_challenge_method=plain redirects with error" do
      get oauth_authorize_path, params: authorize_params(code_challenge_method: "plain")
      assert_response :redirect
      assert_match(/error=invalid_request/, response.location)
    end

    # --- POST /oauth/authorize/start ---------------------------------------

    test "POST /oauth/authorize/start creates verification linked to auth_request and sends email" do
      get oauth_authorize_path, params: authorize_params
      auth_request = OauthAuthorizationRequest.last

      assert_difference -> { EmailVerification.count }, 1 do
        assert_enqueued_emails 1 do
          post oauth_authorize_start_path,
               params: { request_token: auth_request.request_token, email: "newuser@example.com" }
        end
      end
      assert_response :success
      assert_includes response.body, "Check your"

      verification = EmailVerification.last
      assert_equal auth_request.id, verification.oauth_authorization_request_id
      assert_equal "newuser@example.com", verification.email
      assert_equal "newuser@example.com", auth_request.reload.email
    end

    test "POST /oauth/authorize/start with invalid email re-renders form with alert" do
      get oauth_authorize_path, params: authorize_params
      auth_request = OauthAuthorizationRequest.last

      post oauth_authorize_start_path,
           params: { request_token: auth_request.request_token, email: "not-an-email" }
      assert_response :unprocessable_entity
      assert_includes response.body, "valid email"
    end

    test "POST /oauth/authorize/start with expired request_token renders 410" do
      get oauth_authorize_path, params: authorize_params
      auth_request = OauthAuthorizationRequest.last
      auth_request.update!(expires_at: 1.minute.ago)

      post oauth_authorize_start_path,
           params: { request_token: auth_request.request_token, email: "x@example.com" }
      assert_response :gone
    end

    # --- GET /oauth/consent (after magic link click) -----------------------

    test "GET /oauth/consent with valid grant renders consent screen" do
      get oauth_authorize_path, params: authorize_params
      auth_request = OauthAuthorizationRequest.last
      user = User.create!(email: "consent@example.com", email_verified_at: Time.current)
      auth_request.update!(user: user)
      grant = AuthorizationsController.mint_grant(auth_request, user)

      get oauth_consent_path(request_token: auth_request.request_token, grant: grant)
      assert_response :success
      assert_includes response.body, "TestApp"
      assert_includes response.body, "consent@example.com"
      assert_includes response.body, "Allow"
    end

    test "GET /oauth/consent without grant renders 410" do
      get oauth_authorize_path, params: authorize_params
      auth_request = OauthAuthorizationRequest.last

      get oauth_consent_path(request_token: auth_request.request_token)
      assert_response :gone
    end

    test "GET /oauth/consent with stale (expired) grant renders 410" do
      get oauth_authorize_path, params: authorize_params
      auth_request = OauthAuthorizationRequest.last
      user = User.create!(email: "x@example.com", email_verified_at: Time.current)
      auth_request.update!(user: user)
      grant = AuthorizationsController.mint_grant(auth_request, user)

      travel 30.minutes do
        get oauth_consent_path(request_token: auth_request.request_token, grant: grant)
        assert_response :gone
      end
    end

    # --- POST /oauth/consent: allow / deny ---------------------------------

    test "POST /oauth/consent decision=allow creates code and redirects to client" do
      get oauth_authorize_path, params: authorize_params
      auth_request = OauthAuthorizationRequest.last
      user = User.create!(email: "allow@example.com", email_verified_at: Time.current)
      auth_request.update!(user: user)
      grant = AuthorizationsController.mint_grant(auth_request, user)

      assert_difference -> { OauthAuthorizationCode.count }, 1 do
        post oauth_consent_decide_path(request_token: auth_request.request_token),
             params: { decision: "allow", grant: grant }
      end
      assert_response :redirect

      uri = URI.parse(response.location)
      assert_equal "app.example", uri.host
      query = Rack::Utils.parse_nested_query(uri.query)
      assert query["code"].present?
      assert_equal "csrf-token-xyz", query["state"]

      code = OauthAuthorizationCode.last
      assert_equal user.id, code.user_id
      assert_equal @client.id, code.oauth_client_id
      assert_equal @challenge, code.code_challenge
      assert auth_request.reload.consumed?
    end

    test "POST /oauth/consent decision=deny redirects with error access_denied" do
      get oauth_authorize_path, params: authorize_params
      auth_request = OauthAuthorizationRequest.last
      user = User.create!(email: "deny@example.com", email_verified_at: Time.current)
      auth_request.update!(user: user)
      grant = AuthorizationsController.mint_grant(auth_request, user)

      assert_no_difference -> { OauthAuthorizationCode.count } do
        post oauth_consent_decide_path(request_token: auth_request.request_token),
             params: { decision: "deny", grant: grant }
      end
      assert_response :redirect
      query = Rack::Utils.parse_nested_query(URI.parse(response.location).query)
      assert_equal "access_denied", query["error"]
      assert_equal "csrf-token-xyz", query["state"]
    end

    test "POST /oauth/consent without grant renders 410" do
      get oauth_authorize_path, params: authorize_params
      auth_request = OauthAuthorizationRequest.last

      post oauth_consent_decide_path(request_token: auth_request.request_token),
           params: { decision: "allow" }
      assert_response :gone
    end
  end
end

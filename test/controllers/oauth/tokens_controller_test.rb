require "test_helper"

module Oauth
  class TokensControllerTest < ActionDispatch::IntegrationTest
    setup do
      @client = OauthClient.create!(client_name: "TestApp",
                                     redirect_uri_list: ["https://app.example/cb"])
      @user   = User.create!(email: "tk@example.com", email_verified_at: Time.current)
      @verifier  = SecureRandom.urlsafe_base64(32)
      @challenge = Base64.urlsafe_encode64(Digest::SHA256.digest(@verifier), padding: false)
      @code = OauthAuthorizationCode.create!(
        user: @user, oauth_client: @client,
        redirect_uri: "https://app.example/cb",
        scope: "read:analytics",
        code_challenge: @challenge,
        code_challenge_method: "S256"
      )
    end

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

    test "happy path: returns Bearer token + marks code used" do
      assert_difference -> { OauthAccessToken.count }, 1 do
        post_token
      end
      assert_response :success

      data = JSON.parse(response.body)
      assert data["access_token"].start_with?("mcpa_oauth_")
      assert_equal "Bearer", data["token_type"]
      assert data["expires_in"] > 364 * 86_400
      assert_equal "read:analytics", data["scope"]

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

    test "unsupported grant_type returns unsupported_grant_type" do
      post_token(grant_type: "client_credentials")
      assert_response :bad_request
      assert_equal "unsupported_grant_type", JSON.parse(response.body)["error"]
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
  end
end

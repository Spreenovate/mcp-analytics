require "test_helper"

module Oauth
  class ClientsControllerTest < ActionDispatch::IntegrationTest
    test "POST /oauth/register creates a client and returns metadata" do
      body = {
        client_name: "My Cool Client",
        redirect_uris: ["https://app.example.com/callback"],
        scope: "analytics:read"
      }.to_json

      assert_difference -> { OauthClient.count }, 1 do
        post "/oauth/register", params: body, headers: { "Content-Type" => "application/json" }
      end
      assert_response :created

      data = JSON.parse(response.body)
      assert_match(/\Amcpa_client_/, data["client_id"])
      assert_equal ["https://app.example.com/callback"], data["redirect_uris"]
      assert_equal "none", data["token_endpoint_auth_method"]

      client = OauthClient.find_by(client_id: data["client_id"])
      assert client.dynamically_registered?
    end

    test "POST /oauth/register with empty redirect_uris is 400 invalid_redirect_uri" do
      body = { client_name: "X", redirect_uris: [] }.to_json
      post "/oauth/register", params: body, headers: { "Content-Type" => "application/json" }
      assert_response :bad_request
      assert_equal "invalid_redirect_uri", JSON.parse(response.body)["error"]
    end

    test "POST /oauth/register with bad redirect_uri (http non-localhost) returns 400" do
      body = { client_name: "X", redirect_uris: ["http://evil.example.com/cb"] }.to_json
      post "/oauth/register", params: body, headers: { "Content-Type" => "application/json" }
      assert_response :bad_request
      assert_equal "invalid_client_metadata", JSON.parse(response.body)["error"]
    end

    test "POST /oauth/register with non-JSON body returns 400" do
      post "/oauth/register", params: "not-json", headers: { "Content-Type" => "application/json" }
      assert_response :bad_request
    end

    test "successful registration emits client_registered audit event" do
      body = { client_name: "AuditMe",
                redirect_uris: [ "https://app.example.com/callback" ] }.to_json

      assert_difference -> { OauthAuditEvent.where(event: "client_registered").count }, 1 do
        post "/oauth/register", params: body, headers: { "Content-Type" => "application/json" }
      end
      logged = OauthAuditEvent.where(event: "client_registered").last
      assert_equal OauthClient.last.id, logged.oauth_client_id
      assert_equal "AuditMe", logged.metadata_hash["client_name"]
    end
  end
end

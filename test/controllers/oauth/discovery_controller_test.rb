require "test_helper"

module Oauth
  class DiscoveryControllerTest < ActionDispatch::IntegrationTest
    test "authorization-server metadata exposes endpoints + S256" do
      get "/.well-known/oauth-authorization-server"
      assert_response :success
      body = JSON.parse(response.body)

      %w[issuer authorization_endpoint token_endpoint registration_endpoint
         scopes_supported response_types_supported grant_types_supported
         code_challenge_methods_supported token_endpoint_auth_methods_supported].each do |k|
        assert body[k].present?, "missing #{k}"
      end
      assert_includes body["code_challenge_methods_supported"], "S256"
      assert_includes body["grant_types_supported"], "authorization_code"
      assert_includes body["token_endpoint_auth_methods_supported"], "none"
    end

    test "protected-resource metadata points at /mcp + auth server" do
      get "/.well-known/oauth-protected-resource"
      assert_response :success
      body = JSON.parse(response.body)
      assert_match(/\/mcp\z/, body["resource"])
      assert_kind_of Array, body["authorization_servers"]
      assert_includes body["bearer_methods_supported"], "header"
    end

    test "advertises analytics:read and analytics:manage scopes" do
      get "/.well-known/oauth-authorization-server"
      assert_includes JSON.parse(response.body)["scopes_supported"], "analytics:read"
      assert_includes JSON.parse(response.body)["scopes_supported"], "analytics:manage"

      get "/.well-known/oauth-protected-resource"
      assert_includes JSON.parse(response.body)["scopes_supported"], "analytics:read"
      assert_includes JSON.parse(response.body)["scopes_supported"], "analytics:manage"
    end

    test "advertises the revocation endpoint (RFC 7009)" do
      get "/.well-known/oauth-authorization-server"
      body = JSON.parse(response.body)
      assert_match %r{/oauth/revoke\z}, body["revocation_endpoint"]
      assert_includes body["revocation_endpoint_auth_methods_supported"], "none"
    end

    test "advertises resource_parameter_supported (RFC 8707)" do
      get "/.well-known/oauth-authorization-server"
      assert_equal true, JSON.parse(response.body)["resource_parameter_supported"]
    end

    test "advertises refresh_token in grant_types_supported (Block 4)" do
      get "/.well-known/oauth-authorization-server"
      grants = JSON.parse(response.body)["grant_types_supported"]
      assert_includes grants, "authorization_code"
      assert_includes grants, "refresh_token"
    end

    test "advertises op_policy_uri and op_tos_uri pointing at our legal pages" do
      get "/.well-known/oauth-authorization-server"
      body = JSON.parse(response.body)
      assert_match %r{/privacy\z}, body["op_policy_uri"]
      assert_match %r{/terms\z}, body["op_tos_uri"]
    end
  end
end

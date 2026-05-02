module Oauth
  # Serves the two .well-known JSON documents that OAuth 2.1 + RFC 9728
  # (Protected Resource Metadata) clients use to bootstrap the flow.
  #
  # The MCP spec (2025-06-18) tells clients to discover the authorization
  # server via the Protected Resource Metadata document referenced from the
  # WWW-Authenticate header on a 401 response.
  class DiscoveryController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    # GET /.well-known/oauth-authorization-server
    def authorization_server
      render json: {
        issuer: base_url,
        authorization_endpoint: "#{base_url}/oauth/authorize",
        token_endpoint: "#{base_url}/oauth/token",
        registration_endpoint: "#{base_url}/oauth/register",
        scopes_supported: %w[read:analytics],
        response_types_supported: %w[code],
        grant_types_supported: %w[authorization_code],
        code_challenge_methods_supported: %w[S256],
        token_endpoint_auth_methods_supported: %w[none],
        service_documentation: "#{base_url}/"
      }
    end

    # GET /.well-known/oauth-protected-resource
    def protected_resource
      render json: {
        resource: "#{base_url}/mcp",
        authorization_servers: [ base_url ],
        scopes_supported: %w[read:analytics],
        bearer_methods_supported: %w[header],
        resource_documentation: "#{base_url}/"
      }
    end

    private

    def base_url
      ENV.fetch("PUBLIC_BASE_URL", "https://mcp-analytics.com")
    end
  end
end

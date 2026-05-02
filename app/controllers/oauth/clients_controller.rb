module Oauth
  # Dynamic Client Registration per RFC 7591. ChatGPT-Connectors require
  # this; Claude/Cursor work with hardcoded clients but DCR is harmless.
  class ClientsController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    # POST /oauth/register
    def create
      attrs = parse_body
      return render_error("invalid_client_metadata", "Body must be a JSON object", :bad_request) unless attrs.is_a?(Hash)

      redirect_uris = Array(attrs["redirect_uris"])
      if redirect_uris.empty?
        return render_error("invalid_redirect_uri", "redirect_uris is required", :bad_request)
      end

      client = OauthClient.new(
        client_name: attrs["client_name"].presence || "Unnamed Client",
        client_uri: attrs["client_uri"],
        logo_uri: attrs["logo_uri"],
        scope: attrs["scope"].presence || "read:analytics",
        token_endpoint_auth_method: attrs["token_endpoint_auth_method"].presence || "none",
        dynamically_registered: true
      )
      client.redirect_uri_list = redirect_uris

      if client.save
        render json: client_metadata(client), status: :created
      else
        render_error("invalid_client_metadata", client.errors.full_messages.join("; "), :bad_request)
      end
    end

    private

    def parse_body
      raw = request.body.read
      return nil if raw.blank?
      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end

    def render_error(code, description, status)
      render json: { error: code, error_description: description }, status: status
    end

    def client_metadata(client)
      {
        client_id: client.client_id,
        client_id_issued_at: client.created_at.to_i,
        client_name: client.client_name,
        client_uri: client.client_uri,
        logo_uri: client.logo_uri,
        redirect_uris: client.redirect_uri_list,
        scope: client.scope,
        grant_types: %w[authorization_code],
        response_types: %w[code],
        token_endpoint_auth_method: client.token_endpoint_auth_method
      }.compact
    end
  end
end

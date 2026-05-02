module Oauth
  # POST /oauth/token — code → access_token exchange (RFC 6749 §4.1.3).
  # Public clients use PKCE (RFC 7636), no client_secret.
  class TokensController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    # POST /oauth/token
    def create
      grant_type = params[:grant_type].to_s
      return render_error("unsupported_grant_type", "Only authorization_code is supported") unless grant_type == "authorization_code"

      code_value     = params[:code].to_s
      client_id      = params[:client_id].to_s
      redirect_uri   = params[:redirect_uri].to_s
      code_verifier  = params[:code_verifier].to_s

      return render_error("invalid_request", "code is required")          if code_value.empty?
      return render_error("invalid_request", "client_id is required")     if client_id.empty?
      return render_error("invalid_request", "redirect_uri is required")  if redirect_uri.empty?
      return render_error("invalid_request", "code_verifier is required") if code_verifier.empty?

      client = OauthClient.find_by(client_id: client_id)
      return render_error("invalid_client", "Unknown client_id") unless client

      auth_code = OauthAuthorizationCode.find_by(code: code_value, oauth_client_id: client.id)
      return render_error("invalid_grant", "Unknown authorization code")          unless auth_code
      return render_error("invalid_grant", "Authorization code has been used")    if auth_code.used_at.present?
      return render_error("invalid_grant", "Authorization code expired")          unless auth_code.usable?
      return render_error("invalid_grant", "redirect_uri mismatch")               unless auth_code.redirect_uri == redirect_uri
      return render_error("invalid_grant", "PKCE verification failed")            unless auth_code.verify_pkce!(code_verifier)

      access_token = nil
      ActiveRecord::Base.transaction do
        auth_code.mark_used!
        access_token = OauthAccessToken.create!(
          user: auth_code.user,
          oauth_client: client,
          scope: auth_code.scope
        )
      end

      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
      render json: {
        access_token: access_token.token,
        token_type: "Bearer",
        expires_in: (access_token.expires_at - Time.current).to_i,
        scope: access_token.scope
      }
    end

    private

    def render_error(code, description)
      # Per RFC 6749 §5.2, errors are 400 with cache-control: no-store.
      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
      render json: { error: code, error_description: description }, status: :bad_request
    end
  end
end

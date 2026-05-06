module Oauth
  # POST /oauth/token — code → access_token exchange (RFC 6749 §4.1.3).
  # Public clients use PKCE (RFC 7636), no client_secret.
  class TokensController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    # POST /oauth/token
    def create
      unless RateLimit.allow?(key: "oauth-token:#{request.remote_ip}", limit: 30, window: 3600)
        return render_error("temporarily_unavailable", "Too many token requests, try again later.", :too_many_requests)
      end

      grant_type = params[:grant_type].to_s
      return render_error("unsupported_grant_type", "Only authorization_code is supported") unless grant_type == "authorization_code"

      code_value     = params[:code].to_s
      client_id      = params[:client_id].to_s
      redirect_uri   = params[:redirect_uri].to_s
      code_verifier  = params[:code_verifier].to_s
      resource       = params[:resource].presence

      return render_error("invalid_request", "code is required")          if code_value.empty?
      return render_error("invalid_request", "client_id is required")     if client_id.empty?
      return render_error("invalid_request", "redirect_uri is required")  if redirect_uri.empty?
      return render_error("invalid_request", "code_verifier is required") if code_verifier.empty?

      # PKCE verifier shape per RFC 7636 §4.1
      unless code_verifier.length.between?(43, 128) && code_verifier.match?(/\A[A-Za-z0-9\-._~]+\z/)
        return render_error("invalid_request", "code_verifier must be 43-128 chars from the unreserved set")
      end

      # RFC 8707: if the client sent a resource at /token, it MUST equal
      # our canonical MCP URI. (Authorize defaults missing/blank to
      # canonical, so auth_code.resource is always canonical post-Block-3.
      # Pre-Block-3 codes may have nil resource and must still redeem.)
      if resource && resource != canonical_resource
        return render_error("invalid_target", "resource must equal #{canonical_resource}")
      end

      client = OauthClient.find_by(client_id: client_id)
      return render_error("invalid_client", "Unknown client_id") unless client

      access_token = nil
      result = ActiveRecord::Base.transaction do
        # Row-lock the code so two concurrent redemptions can't both succeed.
        auth_code = OauthAuthorizationCode.lock.find_by(code: code_value)
        next [ :unknown ] unless auth_code
        next [ :wrong_client ] unless auth_code.oauth_client_id == client.id
        next [ :used ]    if auth_code.used_at.present?
        next [ :expired ] unless auth_code.usable?
        next [ :redirect_mismatch ] unless auth_code.redirect_uri == redirect_uri
        next [ :pkce_fail ] unless auth_code.verify_pkce!(code_verifier)

        # RFC 8707 binding: every code minted through Block-3 has
        # resource = canonical. If the client sends `resource` here it
        # must match what was bound at /authorize. Missing here is fine —
        # we carry the binding through. Reject downgrade attempts where
        # the code had no binding but the request now claims one.
        if resource.present? && auth_code.resource.present? && auth_code.resource != resource
          next [ :resource_mismatch ]
        end
        if resource.present? && auth_code.resource.nil?
          next [ :resource_mismatch ]
        end

        auth_code.mark_used!
        access_token = OauthAccessToken.create!(
          user: auth_code.user,
          oauth_client: client,
          scope: auth_code.scope,
          resource: auth_code.resource || resource
        )
        [ :ok ]
      end

      case result.first
      when :unknown            then return render_error("invalid_grant", "Unknown authorization code")
      when :wrong_client       then return render_error("invalid_grant", "Authorization code was not issued to this client")
      when :used               then return render_error("invalid_grant", "Authorization code has been used")
      when :expired            then return render_error("invalid_grant", "Authorization code expired")
      when :redirect_mismatch  then return render_error("invalid_grant", "redirect_uri mismatch")
      when :pkce_fail          then return render_error("invalid_grant", "PKCE verification failed")
      when :resource_mismatch  then return render_error("invalid_target", "resource does not match the value used at /authorize")
      end

      Oauth::Audit.log("token_issued",
        user: access_token.user,
        oauth_client: client,
        oauth_access_token: access_token,
        request: request,
        metadata: { scope: access_token.scope, resource: access_token.resource })

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

    def canonical_resource
      Oauth::BaseUrl.canonical_resource
    end

    def render_error(code, description, status = :bad_request)
      # Per RFC 6749 §5.2, errors are 400 with cache-control: no-store.
      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
      render json: { error: code, error_description: description }, status: status
    end
  end
end

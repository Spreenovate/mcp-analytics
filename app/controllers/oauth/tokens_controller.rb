module Oauth
  # POST /oauth/token — token endpoint.
  # Two grant types supported:
  #   - authorization_code (RFC 6749 §4.1.3) — initial issuance
  #   - refresh_token      (RFC 6749 §6 + OAuth 2.1 §4.3.1 rotation)
  # Public clients use PKCE on the code grant; refresh has no PKCE per
  # RFC but rotates the refresh value on every use and detects replay.
  class TokensController < ApplicationController
    include OauthCors
    skip_before_action :verify_authenticity_token, raise: false

    def preflight
      head :no_content
    end

    SUPPORTED_GRANTS = %w[authorization_code refresh_token].freeze

    # POST /oauth/token
    def create
      unless RateLimit.allow?(key: "oauth-token:#{request.remote_ip}", limit: 30, window: 3600)
        return render_error("temporarily_unavailable", "Too many token requests, try again later.", :too_many_requests)
      end

      grant_type = params[:grant_type].to_s
      case grant_type
      when "authorization_code" then authorization_code_grant
      when "refresh_token"      then refresh_token_grant
      else
        render_error("unsupported_grant_type",
          "Supported: #{SUPPORTED_GRANTS.join(', ')}")
      end
    end

    private

    # --- authorization_code grant ----------------------------------------

    def authorization_code_grant
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
      # our canonical MCP URI.
      if resource && resource != canonical_resource
        return render_error("invalid_target", "resource must equal #{canonical_resource}")
      end

      client = OauthClient.find_by(client_id: client_id)
      return render_error("invalid_client", "Unknown client_id") unless client

      access_token = nil
      result = ActiveRecord::Base.transaction do
        auth_code = OauthAuthorizationCode.lock.find_by(code: code_value)
        next [ :unknown ] unless auth_code
        next [ :wrong_client ] unless auth_code.oauth_client_id == client.id
        next [ :used ]    if auth_code.used_at.present?
        next [ :expired ] unless auth_code.usable?
        next [ :redirect_mismatch ] unless auth_code.redirect_uri == redirect_uri
        next [ :pkce_fail ] unless auth_code.verify_pkce!(code_verifier)

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
        metadata: { scope: access_token.scope, resource: access_token.resource, grant: "authorization_code" })

      render_token_response(access_token)
    end

    # --- refresh_token grant ---------------------------------------------
    #
    # OAuth 2.1 §4.3.1 mandates refresh-token rotation for public clients.
    # Reuse of an already-redeemed refresh token is treated as compromise:
    # we revoke every active access_token in the same family (= same
    # user + oauth_client pair). A scope param may only narrow the
    # original grant.
    #
    # Side-channel hygiene: every failure mode renders the same opaque
    # `invalid_grant: "Invalid refresh token"` response. Distinguishing
    # outcomes lives only in the audit log (one row per attempt, with
    # `outcome:` in metadata) so an attacker hitting the endpoint can't
    # enumerate "valid token / wrong client / replay / expired".
    REFRESH_GENERIC_ERROR = "Invalid refresh token".freeze

    def refresh_token_grant
      refresh_value = params[:refresh_token].to_s
      client_id     = params[:client_id].to_s
      requested_scope = params[:scope].to_s

      return render_error("invalid_request", "refresh_token is required") if refresh_value.empty?
      return render_error("invalid_request", "client_id is required")     if client_id.empty?

      client = OauthClient.find_by(client_id: client_id)
      unless client
        audit_refresh_attempt(:unknown_client, request: request,
                               metadata: { client_id_seen: client_id.first(32) })
        return render_error("invalid_grant", REFRESH_GENERIC_ERROR)
      end

      new_token = nil
      old_token_for_audit = nil
      result = ActiveRecord::Base.transaction do
        old_token = OauthAccessToken.lock.find_by(refresh_token: refresh_value)
        next [ :unknown ] unless old_token

        old_token_for_audit = old_token
        next [ :wrong_client ] unless old_token.oauth_client_id == client.id

        # Replay detection: this refresh was already consumed. Treat the
        # whole family (user + client) as compromised. `update_all`
        # issues a direct UPDATE — no SELECT-FOR-UPDATE needed, the
        # row-level lock from the parent `lock.find_by` already
        # serialised concurrent attempts on this refresh value.
        if old_token.refresh_token_used_at.present?
          OauthAccessToken
            .where(user_id: old_token.user_id, oauth_client_id: client.id, revoked_at: nil)
            .update_all(revoked_at: Time.current, refresh_token_used_at: Time.current)
          next [ :replay, old_token ]
        end

        next [ :inactive_refresh ] unless old_token.refresh_active?

        # Optional scope narrowing per RFC 6749 §6: requested scope MUST
        # be a subset of the original. Empty/missing = inherit.
        effective_scope = old_token.scope
        if requested_scope.present?
          unless Oauth::Scopes.granted?(old_token.scope, requested_scope.split(/\s+/))
            next [ :scope_widening ]
          end
          effective_scope = requested_scope
        end

        # Rotate: revoke! is bilateral (sets refresh_token_used_at too).
        old_token.revoke!

        new_token = OauthAccessToken.create!(
          user: old_token.user,
          oauth_client: client,
          scope: effective_scope,
          resource: old_token.resource
        )
        [ :ok, old_token ]
      end

      status, old_token = result

      # One audit row per refresh attempt — uniformity defeats the
      # "row-presence as side-channel" oracle.
      audit_refresh_attempt(status,
        user: (new_token || old_token_for_audit)&.user,
        oauth_client: client,
        oauth_access_token: (new_token || old_token_for_audit),
        request: request,
        metadata: refresh_audit_metadata(status, new_token, old_token))

      case status
      when :ok              then render_token_response(new_token)
      when :scope_widening  then render_error("invalid_scope", "Requested scope must be a subset of the original")
      else                       render_error("invalid_grant", REFRESH_GENERIC_ERROR)
      end
    end

    def audit_refresh_attempt(outcome, **kwargs)
      meta = (kwargs.delete(:metadata) || {}).merge(outcome: outcome)
      Oauth::Audit.log("token_refreshed", **kwargs, metadata: meta)
    end

    def refresh_audit_metadata(status, new_token, old_token)
      base = { status: status }
      base[:scope]    = new_token.scope    if new_token
      base[:resource] = new_token.resource if new_token
      base[:superseded_token_id] = old_token.id if status == :ok && old_token
      base[:replay_of_token_id]  = old_token.id if status == :replay && old_token
      base
    end

    # --- helpers ---------------------------------------------------------

    def render_token_response(access_token)
      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
      payload = {
        access_token: access_token.token,
        # Lowercase per RFC 6749 §5.1 ("bearer" is the registered token
        # type) and matching cloudflare/workers-oauth-provider — strict
        # clients have been seen rejecting "Bearer" with a capital B.
        token_type: "bearer",
        expires_in: (access_token.expires_at - Time.current).to_i,
        scope: access_token.scope
      }
      if access_token.refresh_token.present?
        payload[:refresh_token] = access_token.refresh_token
        payload[:refresh_token_expires_in] =
          (access_token.refresh_token_expires_at - Time.current).to_i
      end
      render json: payload
    end

    def canonical_resource
      Oauth::BaseUrl.canonical_resource
    end

    def render_error(code, description, status = :bad_request)
      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
      render json: { error: code, error_description: description }, status: status
    end
  end
end

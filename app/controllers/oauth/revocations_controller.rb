module Oauth
  # POST /oauth/revoke — RFC 7009 Token Revocation.
  #
  # Public PKCE clients (we have no client_secret) can revoke their own
  # tokens. Per RFC 7009 §2.2 we always respond 200 (even for unknown,
  # already-revoked, or wrong-client tokens) so attackers can't probe
  # token / client existence.
  #
  # `client_id` is REQUIRED on this endpoint. RFC 7009 §2.1 marks client
  # auth optional for public clients, but our setup has no confidential
  # clients — `client_id` is the only ownership signal we have. Without
  # it, anyone who learns a token value (logs, sentry, exfil) could DoS
  # the user by killing their connector. Refresh tokens have a 90-day
  # window, making the unauth-revoke window meaningfully long.
  class RevocationsController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false

    # POST /oauth/revoke
    def create
      unless RateLimit.allow?(key: "oauth-revoke:#{request.remote_ip}", limit: 30, window: 3600)
        return render_error("temporarily_unavailable", "Too many revocation attempts, try again later.", :too_many_requests)
      end

      token_value     = params[:token].to_s
      client_id       = params[:client_id].to_s
      token_type_hint = params[:token_type_hint].to_s

      return render_error("invalid_request", "token is required", :bad_request)     if token_value.empty?
      return render_error("invalid_request", "client_id is required", :bad_request) if client_id.empty?

      # Always emit one audit row per call so the DB-write timing is the
      # same for every outcome (no token-existence side channel via wall
      # clock or audit-log tail). The `outcome` field carries the actual
      # result for reviewers.
      outcome = perform_revocation(token_value, client_id)
      Oauth::Audit.log("token_revoked",
        oauth_client: outcome[:client],
        oauth_access_token: outcome[:token],
        user: outcome[:token]&.user,
        request: request,
        metadata: { hint: token_type_hint, outcome: outcome[:status] })

      response.set_header("Cache-Control", "no-store")
      head :ok
    end

    private

    # Returns { status:, client:, token: }.
    # Status is one of: :revoked, :already_revoked, :wrong_client, :unknown_token.
    #
    # Per RFC 7009 §2.1 a token revocation may target either an access
    # token or a refresh token. We look up by both columns; the caller
    # gets the same uniform 200 response either way.
    def perform_revocation(token_value, client_id)
      client = OauthClient.find_by(client_id: client_id)

      OauthAccessToken.transaction do
        # Lock so two parallel revocations don't both pass the
        # revoked_at-nil check and write conflicting rows.
        access_token = OauthAccessToken.lock.find_by(token: token_value) ||
                       OauthAccessToken.lock.find_by(refresh_token: token_value)

        if access_token.nil?
          { status: :unknown_token, client: client, token: nil }
        elsif client.nil? || access_token.oauth_client_id != client.id
          { status: :wrong_client, client: client, token: access_token }
        elsif access_token.revoked_at.present?
          { status: :already_revoked, client: client, token: access_token }
        else
          # Bilateral kill via OauthAccessToken#revoke! — sets revoked_at
          # and consumes refresh_token_used_at in one atomic update.
          access_token.revoke!
          { status: :revoked, client: client, token: access_token }
        end
      end
    end

    def render_error(code, description, status)
      response.set_header("Cache-Control", "no-store")
      render json: { error: code, error_description: description }, status: status
    end
  end
end

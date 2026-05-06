module Oauth
  # Authorize endpoint per RFC 6749 §4.1 + RFC 7636 (PKCE) + RFC 8252.
  #
  # Flow:
  #  GET  /oauth/authorize             validates params, persists request, renders email form
  #  POST /oauth/authorize/start       email submitted → magic-link sent
  #  GET  /oauth/consent/:token        rendered after the user clicks the magic link
  #                                     (signed grant in URL replaces a session cookie)
  #  POST /oauth/consent/:token        approve/deny → redirect back to client with code|error
  class AuthorizationsController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false, only: [ :start ]

    GRANT_VERIFIER_PURPOSE = "oauth_consent_grant".freeze
    GRANT_LIFETIME = 10.minutes

    before_action :no_store_no_referrer

    # GET /oauth/authorize
    def new
      unless RateLimit.allow?(key: "oauth-authorize:#{request.remote_ip}", limit: 60, window: 3600)
        return render_param_error("temporarily_unavailable", "Too many authorization attempts, try again later.")
      end

      @client = OauthClient.find_by(client_id: params[:client_id])
      return render_param_error("invalid_client", "Unknown client_id") unless @client

      redirect_uri = params[:redirect_uri].to_s
      unless @client.allows_redirect_uri?(redirect_uri)
        return render_param_error("invalid_redirect_uri", "redirect_uri not registered for this client")
      end

      response_type = params[:response_type].to_s
      return redirect_with_error(redirect_uri, "unsupported_response_type", "Only 'code' is supported") unless response_type == "code"

      code_challenge = params[:code_challenge].to_s
      code_challenge_method = params[:code_challenge_method].to_s
      return redirect_with_error(redirect_uri, "invalid_request", "code_challenge required") if code_challenge.empty?
      return redirect_with_error(redirect_uri, "invalid_request", "code_challenge_method must be S256") unless code_challenge_method == "S256"

      requested_scope = params[:scope].presence || @client.scope
      unless Scopes.valid?(requested_scope)
        return redirect_with_error(redirect_uri, "invalid_scope",
          "Supported scopes: #{Scopes::ALL.join(', ')}")
      end

      # RFC 8707 (Resource Indicators for OAuth 2.0). The MCP spec mandates
      # that clients send `resource` and that we bind tokens to the
      # specific MCP server they're meant for. Many clients in the wild
      # still don't send it, so default to canonical when missing — that
      # way every token issued through this server is bound, and the
      # check at the resource server (mcp_controller) can be strict.
      requested_resource = params[:resource].presence || canonical_resource
      if requested_resource != canonical_resource
        return redirect_with_error(redirect_uri, "invalid_target",
          "resource must equal #{canonical_resource}")
      end

      @auth_request = OauthAuthorizationRequest.create!(
        oauth_client: @client,
        redirect_uri: redirect_uri,
        state: params[:state],
        scope: requested_scope,
        resource: requested_resource,
        code_challenge: code_challenge,
        code_challenge_method: code_challenge_method
      )
      render :new
    end

    # POST /oauth/authorize/start
    def start
      @auth_request = OauthAuthorizationRequest.usable.find_by(request_token: params[:request_token])
      unless @auth_request
        flash.now[:alert] = "This authorization request has expired. Please start again from your client."
        return render :expired, status: :gone
      end

      result = Signup.start(
        email: params[:email].to_s,
        ip: request.remote_ip,
        oauth_authorization_request: @auth_request
      )

      if result.ok?
        @client = @auth_request.oauth_client
        @email = result.verification.email
        render :sent
      else
        @client = @auth_request.oauth_client
        flash.now[:alert] = result.error_message
        render :new, status: :unprocessable_entity
      end
    end

    # GET /oauth/consent/:request_token
    def show
      load_consent_or_render_expired or return
      render :consent
    end

    # POST /oauth/consent/:request_token
    def decide
      load_consent_or_render_expired or return

      # Lock the row so two concurrent consent submissions can't each mint a code.
      code = nil
      OauthAuthorizationRequest.transaction do
        @auth_request.lock!
        if @auth_request.consumed?
          render :expired, status: :gone
          return
        end

        if params[:decision] == "allow"
          code = OauthAuthorizationCode.create!(
            user: @auth_request.user,
            oauth_client: @auth_request.oauth_client,
            redirect_uri: @auth_request.redirect_uri,
            scope: @auth_request.scope,
            resource: @auth_request.resource,
            code_challenge: @auth_request.code_challenge,
            code_challenge_method: @auth_request.code_challenge_method
          )
        end
        @auth_request.mark_consumed!
      end

      if code
        Oauth::Audit.log("consent_granted",
          user: @auth_request.user,
          oauth_client: @auth_request.oauth_client,
          request: request,
          metadata: { scope: @auth_request.scope, resource: @auth_request.resource })
        # RFC 9207: include `iss` so strict clients can pin the issuer.
        redirect_to(client_redirect_with(code: code.code,
                                          state: @auth_request.state,
                                          iss: Oauth::BaseUrl.value),
                    allow_other_host: true)
      else
        Oauth::Audit.log("consent_denied",
          user: @auth_request.user,
          oauth_client: @auth_request.oauth_client,
          request: request)
        redirect_to(client_redirect_with(error: "access_denied",
                                          error_description: "User denied access",
                                          state: @auth_request.state,
                                          iss: Oauth::BaseUrl.value),
                    allow_other_host: true)
      end
    end

    # Public so VerificationsController can mint a grant after the magic link
    # is clicked, then redirect to /oauth/consent/:token?grant=...
    def self.mint_grant(auth_request, user)
      Rails.application.message_verifier(GRANT_VERIFIER_PURPOSE).generate(
        { "rid" => auth_request.id, "uid" => user.id },
        expires_in: GRANT_LIFETIME
      )
    end

    private

    def load_consent_or_render_expired
      @auth_request = OauthAuthorizationRequest.usable.find_by(request_token: params[:request_token])
      unless @auth_request
        render :expired, status: :gone
        return false
      end

      grant = params[:grant].to_s
      payload = Rails.application.message_verifier(GRANT_VERIFIER_PURPOSE).verified(grant)
      unless payload.is_a?(Hash) && payload["rid"] == @auth_request.id && payload["uid"] == @auth_request.user_id
        render :expired, status: :gone
        return false
      end

      @client = @auth_request.oauth_client
      @user = @auth_request.user
      @grant = grant
      true
    end

    def canonical_resource
      Oauth::BaseUrl.canonical_resource
    end

    def render_param_error(code, description)
      @code = code
      @description = description
      render :param_error, status: :bad_request
    end

    def redirect_with_error(redirect_uri, code, description)
      redirect_to(append_query(redirect_uri, error: code, error_description: description, state: params[:state]),
                  allow_other_host: true)
    end

    def client_redirect_with(**query)
      append_query(@auth_request.redirect_uri, **query)
    end

    def append_query(uri, **query)
      parsed = URI.parse(uri)
      pairs = URI.decode_www_form(parsed.query.to_s)
      override_keys = query.compact.keys.map(&:to_s)
      pairs.reject! { |k, _| override_keys.include?(k) }
      query.compact.each { |k, v| pairs << [ k.to_s, v.to_s ] }
      parsed.query = URI.encode_www_form(pairs)
      parsed.to_s
    end

    # Consent + authorize pages carry the signed grant in their URL — keep
    # them out of intermediary caches and outbound Referer headers.
    # `same-origin` (not `no-referrer`): Chromium under `no-referrer` sends
    # `Origin: null` on same-origin form POSTs, which breaks Rails' CSRF
    # origin check on POST /oauth/authorize/start and /oauth/consent/:token.
    # `same-origin` still strips the Referer when navigating to the client's
    # redirect_uri (the actual leak risk), while letting our own POSTs
    # carry a proper Origin.
    def no_store_no_referrer
      response.set_header("Cache-Control", "no-store")
      response.set_header("Pragma", "no-cache")
      response.set_header("Referrer-Policy", "same-origin")
    end
  end
end

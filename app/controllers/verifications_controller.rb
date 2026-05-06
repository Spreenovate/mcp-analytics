class VerificationsController < ApplicationController
  before_action :no_referrer_or_store
  before_action :load_verification

  # GET /verify/:token
  #
  # Read-only — renders a confirmation page. NO state change. This is the
  # main defence against `<img src="https://mcp-analytics.com/verify/X">`
  # CSRF: a hostile page can trigger this GET in a victim's browser, but
  # nothing happens server-side beyond rendering. The user has to click
  # the form button (or POST themselves) to actually redeem the link.
  def show
    return render :expired, status: :gone unless @verification

    @client_name = @verification.oauth_flow? ? @verification.oauth_authorization_request.oauth_client.client_name : nil
  end

  # POST /verify/:token
  #
  # Does the actual work: marks verification used, creates the user,
  # establishes a Settings session (plain flow) OR redirects to consent
  # (OAuth flow). The Rails CSRF token in the form provides the second
  # layer of defence; the URL token is the credential.
  def confirm
    return render :expired, status: :gone unless @verification

    # `oauth_flow_expired` is set inside the transaction so the
    # auth_request's freshness is read atomically with the user/verify
    # work — without it, an OAuth flow whose auth_request expired
    # between commit and post-tx check would silently fall through to
    # plain-verify and sign the user into Settings.
    oauth_flow_expired = false

    ActiveRecord::Base.transaction do
      @user = User.find_by(email: @verification.email) ||
              User.create!(email: @verification.email, email_verified_at: Time.current)
      @user.update!(email_verified_at: Time.current) if @user.email_verified_at.nil?

      @verification.mark_used! unless @verification.used_at

      if @verification.oauth_flow?
        auth_request = @verification.oauth_authorization_request
        auth_request.update!(user: @user) if auth_request.user_id.nil?
        oauth_flow_expired = !auth_request.usable?
      end
    end

    if @verification.oauth_flow?
      if oauth_flow_expired
        render :expired, status: :gone
        return
      end
      auth_request = @verification.oauth_authorization_request
      grant = Oauth::AuthorizationsController.mint_grant(auth_request, @user)
      redirect_to oauth_consent_path(request_token: auth_request.request_token, grant: grant)
      return
    end

    # Plain (non-OAuth) verify: clicking the email link AND clicking the
    # confirmation button counts as a fresh sign-in. Establishes a 30-min
    # sliding session for the Settings UI so the user can revoke OAuth
    # connectors without re-emailing themselves.
    sign_in_for_settings(@user)

    @base_url = ENV.fetch("PUBLIC_BASE_URL", "https://mcp-analytics.com")
    render :verified
  end

  private

  def load_verification
    found = EmailVerification.find_by(verify_token: params[:token])
    @verification = (found && found.usable?) ? found : nil
  end

  # The verify URL is a credential — don't let it leak via Referer when
  # the user clicks an outbound link, and don't let intermediate caches
  # keep the response.
  #
  # Use `same-origin` (not `no-referrer`): modern Chromium under
  # `no-referrer` sends `Origin: null` on form POSTs, which breaks
  # Rails' origin-based CSRF check on our own POST /verify/:token.
  # `same-origin` keeps the Referer empty for cross-origin nav (so the
  # token doesn't leak to claude.ai/google/etc.) while letting our own
  # POST carry a proper Origin header.
  def no_referrer_or_store
    response.set_header("Referrer-Policy", "same-origin")
    response.set_header("Cache-Control", "no-store")
  end
end

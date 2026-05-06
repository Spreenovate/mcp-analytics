class VerificationsController < ApplicationController
  before_action :no_referrer_or_store, only: :show

  def show
    @verification = EmailVerification.find_by(verify_token: params[:token])

    if @verification.nil? || !@verification.usable?
      render :expired, status: :gone
      return
    end

    # Idempotent: if a user already exists for this email (someone clicked twice),
    # re-surface their existing token rather than erroring.
    #
    # `oauth_flow_expired` is set inside the transaction (where we can
    # see the auth_request's freshness atomically with the user/verify
    # work) and consumed below. Without this, an OAuth verify whose
    # auth_request expired between commit and the post-tx check would
    # fall through to the plain-verify path and silently sign the user
    # into Settings while displaying their api_token — surprising and
    # not what they asked for.
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

    # Plain (non-OAuth) verify: clicking the email link counts as a fresh
    # sign-in. Establishes a 30-min sliding session for the Settings UI so
    # the user can revoke OAuth connectors without re-emailing themselves.
    sign_in_for_settings(@user)

    @base_url = ENV.fetch("PUBLIC_BASE_URL", "https://mcp-analytics.com")
    @mcp_url_with_token = "#{@base_url}/mcp?token=#{@user.api_token}"
  end

  private

  # The verify URL is a credential and the page renders the api_token in
  # plaintext. Don't let either leak via Referer when the user clicks
  # an outbound link, and don't let intermediate caches keep the page.
  def no_referrer_or_store
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("Cache-Control", "no-store")
  end
end

class SettingsController < ApplicationController
  before_action :require_settings_session
  # The settings page renders the user's legacy api_token in plaintext
  # (inside an HTML element behind a `<details>` toggle). Don't let the
  # response sit in any intermediary cache, and don't leak the page URL
  # via Referer on outbound clicks. `same-origin` (not `no-referrer`) so
  # the Disconnect form's POST still carries a valid Origin header for
  # Rails CSRF — same trade-off as VerificationsController.
  before_action :no_store_same_origin_referrer

  # GET /settings
  def show
    @user = current_settings_user
    @connectors = @user.oauth_access_tokens
                       .active
                       .includes(:oauth_client)
                       .order(created_at: :desc)
  end

  # POST /settings/connectors/:id/revoke
  #
  # Revokes one OauthAccessToken belonging to the signed-in user. Logs to
  # the OAuth audit trail with `outcome: "revoked_by_user"` so the
  # provenance (user-initiated vs. client-initiated) stays clear.
  def revoke_connector
    token = current_settings_user.oauth_access_tokens.find_by(id: params[:id])
    if token.nil?
      redirect_to settings_path, alert: "Connector not found."
      return
    end

    if token.revoked_at.present?
      redirect_to settings_path,
                  notice: "#{token.oauth_client.client_name} was already disconnected."
      return
    end

    token.revoke!
    Oauth::Audit.log("token_revoked",
      user: current_settings_user,
      oauth_client: token.oauth_client,
      oauth_access_token: token,
      request: request,
      metadata: { outcome: "revoked_by_user", source: "settings_ui" })

    redirect_to settings_path, notice: "Disconnected #{token.oauth_client.client_name}."
  end

  # POST /settings/sign_out
  def sign_out
    sign_out_of_settings
    redirect_to root_path, notice: "Signed out."
  end

  private

  def no_store_same_origin_referrer
    response.set_header("Cache-Control", "no-store")
    response.set_header("Pragma", "no-cache")
    response.set_header("Referrer-Policy", "same-origin")
  end
end

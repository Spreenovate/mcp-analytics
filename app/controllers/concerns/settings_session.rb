# Cookie-backed sliding session, narrow-purpose: only used to gate the
# Settings UI where users review and revoke OAuth connectors.
#
# Deliberately separate from any future "log in to use the API" notion —
# MCP authenticates via Bearer or query token, this is web-UI-only.
#
# Session keys we own:
#   session[:settings_user_id]      - id of the verified user
#   session[:settings_user_version] - copy of users.session_version at sign-in;
#                                      mismatch invalidates (defeats cookie
#                                      replay after sign-out)
#   session[:settings_seen_at]      - last seen at (epoch); rotates per request
#
# Sliding 30-min window. Idle that long → session forgotten.
module SettingsSession
  extend ActiveSupport::Concern

  IDLE_TIMEOUT = 30.minutes
  # Tolerate small clock skew between Rails workers; reject anything
  # further in the future as cookie corruption / clock attack.
  FUTURE_SKEW_TOLERANCE = 60.seconds

  included do
    helper_method :current_settings_user, :settings_signed_in?
  end

  def sign_in_for_settings(user)
    # Session-fixation hardening: regenerate the session id on log-in so
    # any pre-existing cookie value can't be reused.
    reset_session
    session[:settings_user_id]      = user.id
    session[:settings_user_version] = user.session_version
    session[:settings_seen_at]      = Time.current.to_i
  end

  def sign_out_of_settings
    # Invalidate every cookie issued for this user before now: the bumped
    # session_version no longer matches the value baked into outstanding
    # cookies. Stops cookie-store replay after explicit sign-out.
    current_settings_user&.bump_session_version!
    reset_session
  end

  def current_settings_user
    return @current_settings_user if defined?(@current_settings_user)
    @current_settings_user = lookup_settings_user
  end

  def settings_signed_in?
    current_settings_user.present?
  end

  def require_settings_session
    return if settings_signed_in?
    redirect_to root_path, alert: "Your session expired. Enter your email on the homepage to get a new sign-in link."
  end

  private

  def lookup_settings_user
    user_id      = session[:settings_user_id]
    seen_at      = session[:settings_seen_at]
    user_version = session[:settings_user_version]
    return nil if user_id.blank? || seen_at.blank? || user_version.blank?

    now_epoch = Time.current.to_i

    # Defence against forged / corrupted cookies that put seen_at in the
    # future — would otherwise make the idle check pass forever.
    if seen_at.to_i > now_epoch + FUTURE_SKEW_TOLERANCE.to_i
      reset_session
      return nil
    end

    if now_epoch - seen_at.to_i > IDLE_TIMEOUT.to_i
      reset_session
      return nil
    end

    user = User.find_by(id: user_id)
    if user.nil? || user.session_version != user_version
      reset_session
      return nil
    end

    # Slide the window: every authenticated request refreshes the timer.
    session[:settings_seen_at] = now_epoch
    user
  end
end

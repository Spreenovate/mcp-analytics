class SettingsController < ApplicationController
  before_action :require_login

  def show
    @user = current_user
    @sites = @user.active_sites.order(:created_at)
    current_month = Date.current.beginning_of_month
    @hits_by_site = UsageCounter
      .where(site_id: @sites.map(&:site_id), month: current_month)
      .pluck(:site_id, :hit_count).to_h
    @base_url = ENV.fetch("PUBLIC_BASE_URL", "https://mcp-analytics.com")
  end

  def regenerate_token
    current_user.regenerate_api_token!
    redirect_to settings_path, notice: "New API token generated. Update your MCP connector URL."
  end

  def destroy_account
    user = current_user
    reset_session
    user.destroy!
    redirect_to root_path, notice: "Account deleted."
  end

  private

  def current_user
    @current_user ||= User.find_by(id: session[:user_id])
  end
  helper_method :current_user

  def require_login
    return if current_user
    redirect_to login_path
  end
end

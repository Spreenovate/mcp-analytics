class VerificationsController < ApplicationController
  def show
    @verification = EmailVerification.find_by(verify_token: params[:token])

    if @verification.nil? || !@verification.usable?
      render :expired, status: :gone
      return
    end

    # Idempotent: if a user already exists for this email (someone clicked twice),
    # re-surface their existing token rather than erroring.
    ActiveRecord::Base.transaction do
      @user = User.find_by(email: @verification.email) ||
              User.create!(email: @verification.email, email_verified_at: Time.current)
      @user.update!(email_verified_at: Time.current) if @user.email_verified_at.nil?

      @verification.mark_used! unless @verification.used_at
    end

    @base_url = ENV.fetch("PUBLIC_BASE_URL", "https://mcp-analytics.com")
    @mcp_url_with_token = "#{@base_url}/mcp?token=#{@user.api_token}"
  end
end

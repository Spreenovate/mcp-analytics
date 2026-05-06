class SignupsController < ApplicationController
  # POST /signup — landing-page email form. Validates, applies anti-abuse
  # rate limits, sends a verification mail. Same Signup.start path the OAuth
  # authorize flow uses, so a user signing up here can later authorize a
  # client without a second account-creation step.
  def create
    result = Signup.start(email: params[:email].to_s, ip: request.remote_ip)

    if result.ok?
      session[:signup_email] = result.verification.email
      redirect_to signup_check_path
    else
      flash[:alert] = result.error_message
      flash[:email] = params[:email].to_s
      flash[:signup_status] = result.status.to_s # 'invalid' | 'rate_limited' — picked up by tracker on home
      redirect_to root_path(anchor: "signup-form")
    end
  end

  # GET /signup/check — "we sent you a link" landing after submission.
  def check
    @email = session[:signup_email]
    redirect_to(root_path) and return if @email.blank?
  end
end

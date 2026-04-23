class SessionsController < ApplicationController
  # Magic-link sign-in for /settings. No passwords, ever.
  before_action :rate_limit!, only: [:create]

  # GET /login
  def new
  end

  # POST /magic-link
  def create
    email = params[:email].to_s.strip.downcase
    user  = User.find_by(email: email)

    if user
      link = user.magic_links.create!
      MagicLinkMailer.sign_in(link).deliver_later
    end

    # Always show the same success page (don't leak whether an email exists).
    render :check_email
  end

  # GET /auth/:token
  def show
    link = MagicLink.find_by(token: params[:token])

    if link.nil? || !link.usable?
      render :expired, status: :gone
      return
    end

    link.mark_used!
    reset_session
    session[:user_id] = link.user_id

    redirect_to settings_path
  end

  # DELETE /logout
  def destroy
    reset_session
    redirect_to root_path
  end

  private

  def rate_limit!
    key = "magic_link_ip:#{request.ip}"
    count = Rails.cache.increment(key, 1, expires_in: 1.hour)
    if count.nil?
      Rails.cache.write(key, 1, expires_in: 1.hour, raw: true)
      return
    end
    if count > 20
      head :too_many_requests
    end
  end
end

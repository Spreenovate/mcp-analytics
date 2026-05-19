class BlogsController < ApplicationController
  before_action :set_locale

  def index
    @posts = BlogPost.all(locale: @locale)
  end

  def show
    @post = BlogPost.find(params[:slug], locale: @locale)
    return head :not_found unless @post
  end

  private

  def set_locale
    @locale = params[:locale] || "en"
  end
end

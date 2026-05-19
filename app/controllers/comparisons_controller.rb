class ComparisonsController < ApplicationController
  before_action :set_locale

  def index
    @comparisons = Comparison.all(locale: @locale)
  end

  def show
    @comparison = Comparison.find(params[:slug], locale: @locale)
    return head :not_found unless @comparison
  end

  private

  def set_locale
    @locale = params[:locale] || "en"
  end
end

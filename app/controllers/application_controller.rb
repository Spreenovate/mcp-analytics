class ApplicationController < ActionController::Base
  include SettingsSession

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  # 301 www → apex. Without this, GSC + crawlers see two duplicate sites
  # and rank-split the canonical signal. Runs before any other action so
  # the redirect happens regardless of which controller would handle it.
  before_action :redirect_to_canonical_host

  private

  def redirect_to_canonical_host
    return unless request.host == "www.mcp-analytics.com"
    redirect_to "https://mcp-analytics.com#{request.fullpath}",
                status: :moved_permanently,
                allow_other_host: true
  end
end

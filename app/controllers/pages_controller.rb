class PagesController < ApplicationController
  def home
    @mcp_url = ENV.fetch("PUBLIC_BASE_URL", "https://mcp-analytics.com") + "/mcp"
  end
end

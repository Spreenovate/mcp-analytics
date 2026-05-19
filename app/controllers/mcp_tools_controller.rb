class McpToolsController < ApplicationController
  def index
    @grouped = McpToolPage.grouped
    @tools = McpToolPage.all
  end

  def show
    @tool = McpToolPage.find(params[:slug].to_s.tr("-", "_"))
    return head :not_found unless @tool
  end
end

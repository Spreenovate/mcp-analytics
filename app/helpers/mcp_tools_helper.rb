module McpToolsHelper
  # A short, natural-language prompt that exercises the tool. Used when
  # the tool has no hand-written examples partial. Falls back to a
  # generic template for tools without specific phrasings.
  def example_prompt_for(tool)
    case tool.name
    when "get_overview"
      "How did mysite.com do last 7 days? Give me a summary."
    when "get_timeseries"
      "Show me pageviews for mysite.com day-by-day for the last 30 days."
    when "compare_periods"
      "Compare last 7 days vs the previous 7 days for mysite.com — pageviews and visitors."
    when "top_pages"
      "What are my top 10 pages on mysite.com last 30 days?"
    when "top_referrers"
      "Where is mysite.com traffic coming from this week?"
    when "top_sources"
      "Which UTM source brought the most visits to mysite.com last month?"
    when "breakdown"
      "Break down visits by browser for mysite.com last 7 days."
    when "list_events"
      "What custom events fired on mysite.com last 14 days?"
    when "event_details"
      "Show me details for the 'signup_started' event on mysite.com — group by referrer."
    when "top_user_agents"
      "Which bots are hitting mysite.com? Show top 20 user agents."
    when "traffic_class_breakdown"
      "How much of mysite.com's traffic is bots vs humans vs AI?"
    when "top_timezones"
      "What timezones are mysite.com visitors in?"
    when "top_languages"
      "What languages do mysite.com visitors speak?"
    when "color_scheme_breakdown"
      "Dark mode vs light mode on mysite.com — what's the split?"
    when "viewport_breakdown"
      "Mobile vs desktop on mysite.com — what's the breakdown?"
    when "engagement_overview"
      "How engaged are mysite.com visitors? Scroll depth and time on page."
    when "list_sites"
      "List my sites."
    when "add_site"
      "Add example.com to my mcp-analytics account in strict privacy mode."
    when "remove_site"
      "Remove example.com from my account."
    when "get_tracking_snippet"
      "Show me the tracking snippet for example.com again."
    when "get_account"
      "Show me my account details — plan, hits this month, sites."
    when "regenerate_api_token"
      "Regenerate my mcp-analytics API token."
    when "get_started_guide"
      "Walk me through using mcp-analytics for the first time."
    else
      "Use the #{tool.name} tool on mysite.com."
    end
  end

  # Build a JSON-RPC payload illustrating a `tools/call` for this tool.
  # Pre-filled with required args and sensible defaults. Returned as a
  # pretty-printed JSON string so it can drop straight into a <pre> block.
  def raw_jsonrpc_example(tool)
    args = {}
    tool.args.each do |a|
      next unless a[:required]
      args[a[:name]] = case a[:name]
      when "site_id"     then "abc12345"
      when "period"      then "last_7_days"
      when "metric"      then "pageviews"
      when "dimension"   then "browser"
      when "domain"      then "example.com"
      when "event_name"  then "signup_started"
      when "period_a"    then "last_7_days"
      when "period_b"    then "previous_7_days"
      else                    "<value>"
      end
    end

    payload = {
      jsonrpc: "2.0",
      id: 1,
      method: "tools/call",
      params: { name: tool.name, arguments: args }
    }
    JSON.pretty_generate(payload).gsub("'", "'\\''")
  end
end

require "click_house"

module Analytics
  # All ClickHouse queries used by the MCP tools live here, scoped by site_id.
  # Callers pass the Site model; we never accept raw site_id strings directly
  # so that the auth layer stays the single enforcement point.
  class Queries
    def initialize(site, client: ClickHouse.client)
      @site   = site
      @client = client
    end

    # --- Overview -----------------------------------------------------------

    # Headline TL;DR for the period. Designed so a single tool call gives
    # the LLM enough to answer "wie lief gestern?" without chaining 4 more
    # tools. Includes vs-previous-period delta, top page, top traffic source,
    # bot share, and the top 3 custom events.
    def overview(period)
      headline_sql = <<~SQL
        SELECT
          countIf(event_name = 'pageview') AS pageviews,
          uniqIf(visitor_id, visitor_id != 0) AS unique_visitors,
          uniq(session_id) AS sessions
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
      SQL
      row = @client.query(headline_sql, params: scope_params(period)).first || {}

      bounce_row = @client.query(<<~SQL, params: scope_params(period)).first || {}
        SELECT
          countIf(cnt = 1) AS bounced,
          count() AS total
        FROM (
          SELECT session_id, count() AS cnt
          FROM events
          WHERE site_id = {site:String} AND traffic_class = 'user'
            AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
          GROUP BY session_id
        )
      SQL

      duration_row = @client.query(<<~SQL, params: scope_params(period)).first || {}
        SELECT avg(sec) AS avg_seconds
        FROM (
          SELECT session_id, dateDiff('second', min(timestamp), max(timestamp)) AS sec
          FROM events
          WHERE site_id = {site:String} AND traffic_class = 'user'
            AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
          GROUP BY session_id
          HAVING count() > 1
        )
      SQL

      # Same headline query, but for the previous equivalent window.
      prev_row = @client.query(headline_sql, params: scope_params(period.previous)).first || {}

      top_page_row = @client.query(<<~SQL, params: scope_params(period)).first || {}
        SELECT url_path, count() AS pageviews
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND event_name = 'pageview'
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
        GROUP BY url_path
        ORDER BY pageviews DESC
        LIMIT 1
      SQL

      top_source_row = @client.query(<<~SQL, params: scope_params(period)).first || {}
        SELECT
          multiIf(utm_source != '', utm_source,
                  referrer_host != '', referrer_host,
                  'direct') AS source,
          count() AS visits
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND event_name = 'pageview'
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
        GROUP BY source
        ORDER BY visits DESC
        LIMIT 1
      SQL

      # Bot share: deliberately does NOT filter traffic_class — we want
      # the ratio. "Bot" here means non-human, so it excludes BOTH 'user'
      # (real visitor with their own browser) AND 'ai_user_action' (a
      # human chatting with ChatGPT/Claude where the assistant fetched
      # the page on their behalf — counts as human attention, just
      # AI-mediated). This matches the IsHuman() semantics in the Go
      # classifier and the `humans` filter alias in top_user_agents.
      bot_row = @client.query(<<~SQL, params: scope_params(period)).first || {}
        SELECT
          countIf(traffic_class NOT IN ('user', 'ai_user_action')) AS bot_hits,
          count() AS total_hits
        FROM events
        WHERE site_id = {site:String}
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
      SQL

      top_events = @client.query(<<~SQL, params: scope_params(period))
        SELECT event_name, count() AS count
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND event_name != 'pageview'
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
        GROUP BY event_name
        ORDER BY count DESC
        LIMIT 3
      SQL

      total = (bounce_row["total"] || 0).to_i
      bounced = (bounce_row["bounced"] || 0).to_i
      pv = (row["pageviews"] || 0).to_i
      prev_pv = (prev_row["pageviews"] || 0).to_i
      bot_hits = (bot_row["bot_hits"] || 0).to_i
      total_hits = (bot_row["total_hits"] || 0).to_i

      {
        pageviews: pv,
        unique_visitors: (row["unique_visitors"] || 0).to_i,
        sessions: (row["sessions"] || 0).to_i,
        bounce_rate: total.zero? ? 0.0 : (bounced.to_f / total).round(4),
        avg_session_duration_seconds: (duration_row["avg_seconds"] || 0).to_f.round(1),
        pageviews_change_pct: prev_pv.zero? ? nil : ((pv - prev_pv).to_f / prev_pv).round(4),
        previous_period: { from: period.previous.from_sql, to: period.previous.to_sql, pageviews: prev_pv },
        top_page: top_page_row["url_path"] ? { url_path: top_page_row["url_path"], pageviews: top_page_row["pageviews"].to_i } : nil,
        top_source: top_source_row["source"] ? { source: top_source_row["source"], visits: top_source_row["visits"].to_i } : nil,
        bot_share: total_hits.zero? ? 0.0 : (bot_hits.to_f / total_hits).round(4),
        top_events: top_events.map { |r| { event_name: r["event_name"], count: r["count"].to_i } }
      }
    end

    # --- Time series --------------------------------------------------------

    def timeseries(metric, period, granularity: "day")
      bucket = bucket_fn(granularity)
      metric_sql = metric_expression(metric)

      sql = <<~SQL
        SELECT #{bucket}(timestamp) AS bucket, #{metric_sql} AS value
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
        GROUP BY bucket
        ORDER BY bucket
      SQL

      @client.query(sql, params: scope_params(period)).map do |row|
        { "timestamp" => row["bucket"], "value" => row["value"].to_i }
      end
    end

    # --- Top lists ----------------------------------------------------------

    def top_pages(period, limit: 10)
      sql = <<~SQL
        SELECT
          url_path,
          count() AS pageviews,
          uniqIf(visitor_id, visitor_id != 0) AS unique_visitors
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND event_name = 'pageview'
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
        GROUP BY url_path
        ORDER BY pageviews DESC
        LIMIT {limit:UInt32}
      SQL

      @client.query(sql, params: scope_params(period).merge(limit: limit)).map do |r|
        { "url_path" => r["url_path"],
          "pageviews" => r["pageviews"].to_i,
          "unique_visitors" => r["unique_visitors"].to_i }
      end
    end

    def top_referrers(period, limit: 10)
      total = referrer_total(period)

      sql = <<~SQL
        SELECT referrer_host, count() AS visits
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND event_name = 'pageview'
          AND referrer_host != ''
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
        GROUP BY referrer_host
        ORDER BY visits DESC
        LIMIT {limit:UInt32}
      SQL

      rows = @client.query(sql, params: scope_params(period).merge(limit: limit))
      rows.map do |r|
        visits = r["visits"].to_i
        {
          "referrer_host" => r["referrer_host"],
          "visits" => visits,
          "percentage_of_total" => total.zero? ? 0.0 : (visits.to_f / total).round(4)
        }
      end
    end

    def top_sources(period, limit: 10)
      sql = <<~SQL
        SELECT utm_source, utm_medium, utm_campaign, count() AS visits
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND event_name = 'pageview'
          AND (utm_source != '' OR utm_medium != '' OR utm_campaign != '')
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
        GROUP BY utm_source, utm_medium, utm_campaign
        ORDER BY visits DESC
        LIMIT {limit:UInt32}
      SQL

      @client.query(sql, params: scope_params(period).merge(limit: limit)).map do |r|
        {
          "utm_source"   => r["utm_source"],
          "utm_medium"   => r["utm_medium"],
          "utm_campaign" => r["utm_campaign"],
          "visits"       => r["visits"].to_i
        }
      end
    end

    def breakdown(dimension, period, limit: 10)
      column = {
        "browser"     => "browser",
        "os"          => "os",
        "device_type" => "device_type",
        "country"     => "country"
      }[dimension.to_s]
      raise ArgumentError, "unknown dimension: #{dimension.inspect}" unless column

      if column == "country"
        return [ { "note" => "geo not enabled in MVP" } ]
      end

      sql = <<~SQL
        SELECT #{column} AS value, count() AS visits
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND event_name = 'pageview'
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
        GROUP BY value
        ORDER BY visits DESC
        LIMIT {limit:UInt32}
      SQL

      rows = @client.query(sql, params: scope_params(period).merge(limit: limit))
      total = rows.sum { |r| r["visits"].to_i }

      rows.map do |r|
        visits = r["visits"].to_i
        {
          "value" => r["value"],
          "visits" => visits,
          "percentage" => total.zero? ? 0.0 : (visits.to_f / total).round(4)
        }
      end
    end

    def list_events(period)
      sql = <<~SQL
        SELECT event_name,
               count() AS count,
               uniq(session_id) AS unique_sessions
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
        GROUP BY event_name
        ORDER BY count DESC
      SQL

      @client.query(sql, params: scope_params(period)).map do |r|
        {
          "event_name" => r["event_name"],
          "count" => r["count"].to_i,
          "unique_sessions" => r["unique_sessions"].to_i
        }
      end
    end

    def event_details(event_name, period, group_by_property: nil)
      if group_by_property
        sql = <<~SQL
          SELECT prop_values[indexOf(prop_keys, {prop:String})] AS value,
                 count() AS count
          FROM events
          WHERE site_id = {site:String} AND traffic_class = 'user'
            AND event_name = {event:String}
            AND has(prop_keys, {prop:String})
            AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
          GROUP BY value
          ORDER BY count DESC
          LIMIT 100
        SQL

        return @client.query(sql, params: scope_params(period).merge(event: event_name, prop: group_by_property)).map do |r|
          { "property_value" => r["value"], "count" => r["count"].to_i }
        end
      end

      totals_sql = <<~SQL
        SELECT count() AS total_count,
               uniq(session_id) AS sessions_with_event
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND event_name = {event:String}
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
      SQL

      totals = @client.query(totals_sql, params: scope_params(period).merge(event: event_name)).first || {}

      pages_sql = <<~SQL
        SELECT url_path, count() AS count
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND event_name = {event:String}
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
        GROUP BY url_path
        ORDER BY count DESC
        LIMIT 10
      SQL

      top_pages = @client.query(pages_sql, params: scope_params(period).merge(event: event_name)).map do |r|
        { "url_path" => r["url_path"], "count" => r["count"].to_i }
      end

      {
        "total_count" => (totals["total_count"] || 0).to_i,
        "sessions_with_event" => (totals["sessions_with_event"] || 0).to_i,
        "top_pages_with_event" => top_pages
      }
    end

    def compare(metric, period_a, period_b)
      a = scalar_metric(metric, period_a)
      b = scalar_metric(metric, period_b)
      abs = a - b
      pct = b.zero? ? nil : (abs.to_f / b).round(4)
      { "a_value" => a, "b_value" => b, "absolute_change" => abs, "percent_change" => pct }
    end

    # --- Stufe-2 client signals --------------------------------------------
    #
    # All these query the user-side fields populated from privacy-clean Web
    # APIs (Intl.DateTimeFormat, navigator.language, matchMedia, innerWidth,
    # Page Visibility, scroll). Aggregable, not personally-identifiable.

    def top_timezones(period, limit: 25)
      simple_breakdown_query("timezone", period, limit: limit, key_alias: "timezone")
    end

    def top_languages(period, limit: 25)
      simple_breakdown_query("language", period, limit: limit, key_alias: "language")
    end

    def color_scheme_breakdown(period)
      sql = <<~SQL
        SELECT color_scheme, count() AS hits
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND event_name = 'pageview'
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
        GROUP BY color_scheme
        ORDER BY hits DESC
      SQL
      rows = @client.query(sql, params: scope_params(period))
      total = rows.sum { |r| r["hits"].to_i }
      rows.map do |r|
        hits = r["hits"].to_i
        {
          "color_scheme" => r["color_scheme"].to_s.empty? ? "unknown" : r["color_scheme"],
          "hits" => hits,
          "percentage" => total.zero? ? 0.0 : (hits.to_f / total).round(4)
        }
      end
    end

    # Bucketed viewport-width distribution: gives the LLM enough to say
    # "70% of your traffic is on mobile-width viewports" without raw pixel dumps.
    def viewport_breakdown(period)
      sql = <<~SQL
        SELECT
          multiIf(
            viewport_w = 0, 'unknown',
            viewport_w < 480, 'mobile_xs',
            viewport_w < 768, 'mobile',
            viewport_w < 1024, 'tablet',
            viewport_w < 1440, 'desktop',
            'desktop_xl'
          ) AS bucket,
          count() AS hits
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND event_name = 'pageview'
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
        GROUP BY bucket
        ORDER BY hits DESC
      SQL
      rows = @client.query(sql, params: scope_params(period))
      total = rows.sum { |r| r["hits"].to_i }
      rows.map do |r|
        hits = r["hits"].to_i
        {
          "bucket" => r["bucket"],
          "hits" => hits,
          "percentage" => total.zero? ? 0.0 : (hits.to_f / total).round(4)
        }
      end
    end

    # Real reading-time + scroll-depth from the engagement beacon. Pageview
    # rows are not counted; only event_name='engagement' rows have these fields.
    def engagement_overview(period)
      sql = <<~SQL
        SELECT
          count() AS engaged_pages,
          avg(engagement_seconds) AS avg_seconds,
          quantile(0.5)(engagement_seconds) AS median_seconds,
          quantile(0.9)(engagement_seconds) AS p90_seconds,
          avg(scroll_depth) AS avg_scroll_depth,
          quantile(0.5)(scroll_depth) AS median_scroll_depth
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND event_name = 'engagement'
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
      SQL
      row = @client.query(sql, params: scope_params(period)).first || {}
      {
        "engaged_pages" => (row["engaged_pages"] || 0).to_i,
        "avg_engagement_seconds" => (row["avg_seconds"] || 0).to_f.round(1),
        "median_engagement_seconds" => (row["median_seconds"] || 0).to_f.round(1),
        "p90_engagement_seconds" => (row["p90_seconds"] || 0).to_f.round(1),
        "avg_scroll_depth_pct" => (row["avg_scroll_depth"] || 0).to_f.round(1),
        "median_scroll_depth_pct" => (row["median_scroll_depth"] || 0).to_f.round(1)
      }
    end

    # --- Bots & user-agents -------------------------------------------------

    # Top user-agents grouped by traffic_class. Default queries hide
    # everything except real visitors; this tool deliberately includes
    # the rest so the customer can see who's actually fetching the site
    # (8-class Phase 2 taxonomy: user / ai_user_action / ai_search /
    # ai_training / search_index / social_unfurl / scanner / bot_other).
    #
    # The `humans` filter alias expands to (user, ai_user_action) — used
    # for "real human attention including AI-mediated browsing".
    #
    # SQL injection note: `traffic_class` is interpolated through CH's
    # parameter mechanism for single-value filters and through a
    # whitelist-validated IN-list for the alias case. We never accept
    # arbitrary strings into the WHERE clause.
    def top_user_agents(period, limit: 25, traffic_class: nil)
      where_class, extra_params = traffic_class_filter(traffic_class)
      sql = <<~SQL
        SELECT user_agent, traffic_class, count() AS hits
        FROM events
        WHERE site_id = {site:String}
          #{where_class}
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
          AND user_agent != ''
        GROUP BY user_agent, traffic_class
        ORDER BY hits DESC
        LIMIT {limit:UInt32}
      SQL

      params = scope_params(period).merge(limit: limit).merge(extra_params)

      @client.query(sql, params: params).map do |r|
        {
          "user_agent"    => r["user_agent"],
          "traffic_class" => r["traffic_class"],
          "hits"          => r["hits"].to_i
        }
      end
    end

    # Aggregate hit counts per traffic_class — quick "X% of yesterday's
    # traffic was bots" answer.
    def traffic_class_breakdown(period)
      sql = <<~SQL
        SELECT traffic_class, count() AS hits
        FROM events
        WHERE site_id = {site:String}
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
        GROUP BY traffic_class
        ORDER BY hits DESC
      SQL

      rows = @client.query(sql, params: scope_params(period))
      total = rows.sum { |r| r["hits"].to_i }
      rows.map do |r|
        hits = r["hits"].to_i
        {
          "traffic_class" => r["traffic_class"],
          "hits"          => hits,
          "percentage"    => total.zero? ? 0.0 : (hits.to_f / total).round(4)
        }
      end
    end

    private

    # Phase-2 traffic_class values. Kept in lockstep with the Go
    # classifier's class.go constants — drift is caught by the daily
    # AI-crawler-schema-check workflow which compares both.
    PHASE2_CLASSES = %w[
      user ai_user_action ai_search ai_training
      search_index social_unfurl scanner bot_other
    ].freeze

    # Filter aliases that expand to a set of underlying classes. Add
    # entries here for "give me everything in bucket X" semantics
    # without having callers enumerate the underlying values.
    TRAFFIC_CLASS_ALIASES = {
      "humans" => %w[user ai_user_action]
    }.freeze

    # traffic_class_filter validates the requested filter and returns
    # the SQL WHERE fragment + parameter map. Whitelisted: any value
    # in PHASE2_CLASSES, plus aliases in TRAFFIC_CLASS_ALIASES, plus
    # `nil`/blank (= no filter, default behavior of the calling tool).
    # Any other value is treated as `nil` (defensive: don't 500 on a
    # client that sends a typo, just unfiltered the query).
    def traffic_class_filter(value)
      return ["", {}] if value.blank?
      v = value.to_s
      if (members = TRAFFIC_CLASS_ALIASES[v])
        # Build IN-list with positional CH params (tc0, tc1, ...).
        placeholders = members.each_with_index.map { |_, i| "{tc#{i}:String}" }
        params = members.each_with_index.to_h { |m, i| [:"tc#{i}", m] }
        return ["AND traffic_class IN (#{placeholders.join(', ')})", params]
      end
      if PHASE2_CLASSES.include?(v)
        return ["AND traffic_class = {tclass:String}", { tclass: v }]
      end
      # Unknown value — silently drop the filter rather than fail the
      # query. The MCP schema enum prevents this for well-behaved
      # clients; this is just defense-in-depth for poorly-behaved ones.
      ["", {}]
    end

    # Shared helper for "top values of one column" with percentage breakdown.
    def simple_breakdown_query(column, period, limit:, key_alias:)
      sql = <<~SQL
        SELECT #{column} AS value, count() AS hits
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND event_name = 'pageview'
          AND #{column} != ''
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
        GROUP BY value
        ORDER BY hits DESC
        LIMIT {limit:UInt32}
      SQL
      rows = @client.query(sql, params: scope_params(period).merge(limit: limit))
      total = rows.sum { |r| r["hits"].to_i }
      rows.map do |r|
        hits = r["hits"].to_i
        {
          key_alias => r["value"],
          "hits" => hits,
          "percentage" => total.zero? ? 0.0 : (hits.to_f / total).round(4)
        }
      end
    end

    def scope_params(period)
      { site: @site.site_id, from: period.from_sql, to: period.to_sql }
    end

    def referrer_total(period)
      row = @client.query(<<~SQL, params: scope_params(period)).first || {}
        SELECT count() AS total
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND event_name = 'pageview'
          AND referrer_host != ''
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
      SQL
      (row["total"] || 0).to_i
    end

    def bucket_fn(granularity)
      case granularity.to_s
      when "hour" then "toStartOfHour"
      when "week" then "toStartOfWeek"
      else "toStartOfDay"
      end
    end

    def metric_expression(metric)
      case metric.to_s
      when "pageviews" then "countIf(event_name = 'pageview')"
      when "visitors"  then "uniqIf(visitor_id, visitor_id != 0)"
      when "sessions"  then "uniq(session_id)"
      else raise ArgumentError, "unknown metric: #{metric.inspect}"
      end
    end

    def scalar_metric(metric, period)
      sql = <<~SQL
        SELECT #{metric_expression(metric)} AS value
        FROM events
        WHERE site_id = {site:String} AND traffic_class = 'user'
          AND timestamp BETWEEN {from:DateTime64(3)} AND {to:DateTime64(3)}
      SQL
      row = @client.query(sql, params: scope_params(period)).first || {}
      (row["value"] || 0).to_i
    end
  end
end

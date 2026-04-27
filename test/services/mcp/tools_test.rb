require "test_helper"

module Mcp
  class ToolsTest < ActiveSupport::TestCase
    setup do
      # Test env defaults to :null_store, which makes RateLimit a no-op.
      # Swap in a real memory store so rate-limit assertions are meaningful.
      @prev_cache = Rails.cache
      Rails.cache = ActiveSupport::Cache::MemoryStore.new

      @user = User.create!(email: "tools@example.com", email_verified_at: Time.current)
      @site = @user.sites.create!(domain: "example.com", privacy_mode: "strict")
      @request = Struct.new(:remote_ip).new("203.0.113.1")
    end

    teardown do
      Rails.cache = @prev_cache
    end

    def auth_tools
      Tools.new(user: @user, request: @request)
    end

    def anon_tools
      Tools.new(user: nil, request: @request)
    end

    # --- register_account ---------------------------------------------------

    test "register_account creates EmailVerification and returns placeholder" do
      assert_difference -> { EmailVerification.count }, 1 do
        result = anon_tools.register_account("email" => "new@example.com")
        assert_match(/\Apu_/, result["pending_user_id"])
        assert_equal "DUMMY_SITE_ID_REPLACE_AFTER_VERIFY", result["placeholder_site_id"]
      end
    end

    test "register_account rejects invalid email" do
      assert_raises(ArgumentError) { anon_tools.register_account("email" => "nope") }
    end

    test "register_account rejects disposable domain" do
      assert_raises(ArgumentError) do
        anon_tools.register_account("email" => "x@mailinator.com")
      end
    end

    test "register_account enforces 3/IP/hour limit" do
      3.times do |i|
        anon_tools.register_account("email" => "u#{i}@example.com")
      end
      err = assert_raises(Tools::RateLimitedError) do
        anon_tools.register_account("email" => "u4@example.com")
      end
      assert_match(/network/i, err.message)
    end

    test "register_account enforces 5/email-domain/day limit" do
      # Use distinct IPs to bypass IP limits.
      5.times do |i|
        req = Struct.new(:remote_ip).new("10.0.0.#{i}")
        Tools.new(user: nil, request: req).register_account("email" => "x#{i}@onedomain.com")
      end
      req6 = Struct.new(:remote_ip).new("10.0.0.99")
      err = assert_raises(Tools::RateLimitedError) do
        Tools.new(user: nil, request: req6).register_account("email" => "x6@onedomain.com")
      end
      assert_match(/email domain/, err.message)
    end

    # --- get_started_guide --------------------------------------------------

    test "get_started_guide returns markdown content" do
      result = anon_tools.get_started_guide({})
      assert result["markdown"].present?
    end

    # --- list_sites / add_site / remove_site --------------------------------

    test "list_sites returns user's active sites with current-month hits" do
      UsageCounter.create!(site_id: @site.site_id,
                           month: Date.current.beginning_of_month, hit_count: 42)
      result = auth_tools.list_sites({})
      assert_equal 1, result.length
      assert_equal @site.site_id, result.first["site_id"]
      assert_equal 42, result.first["hits_this_month"]
      assert_equal 100_000, result.first["plan_limit"]
    end

    test "add_site creates site and returns snippet" do
      assert_difference -> { @user.sites.count }, 1 do
        result = auth_tools.add_site("domain" => "new.com", "privacy_mode" => "default")
        assert_match(/\A[a-z2-7]{8}\z/, result["site_id"])
        assert_equal "default", result["privacy_mode"]
        assert_includes result["tracking_snippet"], result["site_id"]
      end
    end

    test "add_site rejects unknown privacy_mode" do
      assert_raises(ArgumentError) do
        auth_tools.add_site("domain" => "new.com", "privacy_mode" => "wild")
      end
    end

    test "add_site enforces 10/day per user" do
      # setup already created one site for @user, so 9 more reach the cap.
      9.times { |i| auth_tools.add_site("domain" => "d#{i}.com") }
      assert_raises(Tools::RateLimitedError) do
        auth_tools.add_site("domain" => "d11.com")
      end
    end

    test "remove_site soft-deletes and excludes from list_sites" do
      auth_tools.remove_site("site_id" => @site.site_id)
      assert_not @site.reload.active?
      assert_empty auth_tools.list_sites({})
    end

    test "remove_site raises NotFoundError for unknown site" do
      assert_raises(Tools::NotFoundError) do
        auth_tools.remove_site("site_id" => "doesnotexist")
      end
    end

    test "find_site! is scoped to current user (no cross-tenant access)" do
      other = User.create!(email: "other@example.com")
      other_site = other.sites.create!(domain: "other.com", privacy_mode: "strict")

      assert_raises(Tools::NotFoundError) do
        auth_tools.get_tracking_snippet("site_id" => other_site.site_id)
      end
    end

    # --- get_tracking_snippet -----------------------------------------------

    test "get_tracking_snippet returns snippet HTML containing the site_id" do
      result = auth_tools.get_tracking_snippet("site_id" => @site.site_id)
      assert_includes result["snippet_html"], @site.site_id
    end

    test "snippet for strict mode has no mode-specific attributes" do
      strict = @user.sites.create!(domain: "s.com", privacy_mode: "strict")
      html = auth_tools.get_tracking_snippet("site_id" => strict.site_id)["snippet_html"]
      assert_not_includes html, "data-persistent"
      assert_not_includes html, "data-respect-dnt"
    end

    test "snippet for default mode has no mode-specific attributes" do
      default = @user.sites.create!(domain: "d.com", privacy_mode: "default")
      html = auth_tools.get_tracking_snippet("site_id" => default.site_id)["snippet_html"]
      assert_not_includes html, "data-persistent"
      assert_not_includes html, "data-respect-dnt"
    end

    test "snippet for all mode opts into persistent visitor id and ignores DNT" do
      allsite = @user.sites.create!(domain: "a.com", privacy_mode: "all")
      html = auth_tools.get_tracking_snippet("site_id" => allsite.site_id)["snippet_html"]
      assert_includes html, 'data-persistent="true"'
      assert_includes html, 'data-respect-dnt="false"'
    end

    # --- get_account / regenerate_api_token ---------------------------------

    test "get_account returns user info with truncated token" do
      result = auth_tools.get_account({})
      assert_equal @user.email, result["email"]
      assert_equal "free", result["plan"]
      assert_equal 1, result["total_sites"]
      assert_equal 10, result["api_token_first_chars"].length
    end

    test "regenerate_api_token returns a new token + MCP URL" do
      old = @user.api_token
      result = auth_tools.regenerate_api_token({})
      assert_not_equal old, result["api_token"]
      assert_includes result["mcp_url"], result["api_token"]
    end

    # --- Analytics tools (mocked ClickHouse) --------------------------------

    test "get_overview shapes ClickHouse rows into the expected hash" do
      stub_clickhouse([
        [{ "pageviews" => 10, "unique_visitors" => 4, "sessions" => 5 }],
        [{ "bounced" => 2, "total" => 5 }],
        [{ "avg_seconds" => 42.5 }]
      ]) do
        result = auth_tools.get_overview("site_id" => @site.site_id, "period" => "last_7_days")
        assert_equal 10, result[:pageviews]
        assert_equal 4,  result[:unique_visitors]
        assert_equal 5,  result[:sessions]
        assert_equal 0.4, result[:bounce_rate]
        assert_equal 42.5, result[:avg_session_duration_seconds]
      end
    end

    test "get_timeseries returns timestamp/value pairs" do
      stub_clickhouse([[
        { "bucket" => "2026-04-22", "value" => 7 },
        { "bucket" => "2026-04-23", "value" => 11 }
      ]]) do
        result = auth_tools.get_timeseries(
          "site_id" => @site.site_id, "metric" => "pageviews",
          "period" => "last_7_days", "granularity" => "day"
        )
        assert_equal 2, result.length
        assert_equal 11, result.last["value"]
      end
    end

    test "top_pages returns shaped rows" do
      stub_clickhouse([[
        { "url_path" => "/", "pageviews" => 50, "unique_visitors" => 30 }
      ]]) do
        result = auth_tools.top_pages("site_id" => @site.site_id, "period" => "last_7_days")
        assert_equal "/", result.first["url_path"]
        assert_equal 50, result.first["pageviews"]
      end
    end

    test "breakdown returns 'geo not enabled' note for country in MVP" do
      result = auth_tools.breakdown(
        "site_id" => @site.site_id, "dimension" => "country", "period" => "last_7_days"
      )
      assert_equal "geo not enabled in MVP", result.first["note"]
    end

    test "breakdown rejects unknown dimension" do
      assert_raises(ArgumentError) do
        auth_tools.breakdown("site_id" => @site.site_id, "dimension" => "moonphase",
                             "period" => "last_7_days")
      end
    end

    test "list_events returns shaped rows" do
      stub_clickhouse([[
        { "event_name" => "pageview", "count" => 100, "unique_sessions" => 40 },
        { "event_name" => "signup",   "count" =>   5, "unique_sessions" =>  5 }
      ]]) do
        result = auth_tools.list_events("site_id" => @site.site_id, "period" => "last_7_days")
        assert_equal 2, result.length
        assert_equal "pageview", result.first["event_name"]
      end
    end

    test "compare_periods computes absolute and percent change" do
      stub_clickhouse([
        [{ "value" => 100 }],   # period_a scalar
        [{ "value" =>  80 }]    # period_b scalar
      ]) do
        result = auth_tools.compare_periods(
          "site_id" => @site.site_id, "metric" => "pageviews",
          "period_a" => "last_7_days", "period_b" => "last_30_days"
        )
        assert_equal 100, result["a_value"]
        assert_equal  80, result["b_value"]
        assert_equal  20, result["absolute_change"]
        assert_equal 0.25, result["percent_change"]
      end
    end

    test "top_user_agents returns shaped rows with traffic_class" do
      stub_clickhouse([[
        { "user_agent" => "Mozilla/5.0 ChatGPT-User/1.0", "traffic_class" => "bot",  "hits" => 12 },
        { "user_agent" => "Mozilla/5.0 (Macintosh) Safari/605", "traffic_class" => "user", "hits" =>  8 }
      ]]) do
        result = auth_tools.top_user_agents("site_id" => @site.site_id, "period" => "today")
        assert_equal 2, result.length
        assert_equal "bot", result.first["traffic_class"]
        assert_equal 12,    result.first["hits"]
      end
    end

    test "traffic_class_breakdown returns percentages summing to ~1.0" do
      stub_clickhouse([[
        { "traffic_class" => "user", "hits" => 80 },
        { "traffic_class" => "bot",  "hits" => 20 }
      ]]) do
        result = auth_tools.traffic_class_breakdown("site_id" => @site.site_id, "period" => "today")
        assert_equal 2, result.length
        assert_equal 0.8, result.first["percentage"]
        assert_equal 0.2, result.last["percentage"]
      end
    end

    test "default analytics queries do NOT include bot traffic" do
      # Verify the SQL emitted by overview includes the traffic_class filter.
      captured = []
      fake = Object.new
      fake.define_singleton_method(:query) do |sql, **_kwargs|
        captured << sql
        []
      end
      ClickHouse.singleton_class.alias_method(:__orig_client, :client)
      ClickHouse.singleton_class.define_method(:client) { fake }
      begin
        auth_tools.get_overview("site_id" => @site.site_id, "period" => "today")
      ensure
        ClickHouse.singleton_class.alias_method(:client, :__orig_client)
        ClickHouse.singleton_class.remove_method(:__orig_client)
      end
      assert captured.all? { |sql| sql.include?("traffic_class = 'user'") },
        "every default query must filter out bot traffic"
    end

    private

    # Stubs ClickHouse.client to return queued result sets in order.
    # Pass an array of result arrays; each `query` call pops the next.
    def stub_clickhouse(result_queue)
      fake = Object.new
      queue = result_queue.dup
      fake.define_singleton_method(:query) do |_sql, **_kwargs|
        queue.shift || []
      end
      ClickHouse.singleton_class.alias_method(:__orig_client, :client)
      ClickHouse.singleton_class.define_method(:client) { fake }
      yield
    ensure
      ClickHouse.singleton_class.alias_method(:client, :__orig_client)
      ClickHouse.singleton_class.remove_method(:__orig_client)
    end
  end
end

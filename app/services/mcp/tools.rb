module Mcp
  # Tool implementations. Each method takes the parsed arguments hash and
  # returns data that will be serialized into an MCP tools/call result.
  #
  # Authentication and rate-limiting happen in the controller. By the time a
  # call reaches here the tool is known-callable for the current auth state.
  class Tools
    PLACEHOLDER_SITE_ID = "DUMMY_SITE_ID_REPLACE_AFTER_VERIFY".freeze

    def initialize(user: nil, request: nil)
      @user = user
      @request = request
    end

    # --- Unauthenticated ----------------------------------------------------

    def register_account(args)
      email = args["email"].to_s.strip.downcase
      raise ArgumentError, "email required" if email.empty?
      raise ArgumentError, "invalid email" unless email.match?(URI::MailTo::EMAIL_REGEXP)

      if disposable_email_domain?(email)
        raise ArgumentError, "disposable email domains are not supported"
      end

      verification = EmailVerification.create!(email: email)

      VerificationMailer.verify(verification).deliver_later

      {
        "pending_user_id" => verification.pending_user_id,
        "placeholder_site_id" => PLACEHOLDER_SITE_ID,
        "message" => "Bestätigungsmail an #{email} gesendet. " \
          "Du kannst jetzt schon den Tracking-Code mit dem Platzhalter " \
          "#{PLACEHOLDER_SITE_ID} einbauen. Nach Verifizierung tauschst du " \
          "den Platzhalter gegen die echte Site-ID aus."
      }
    end

    def get_started_guide(_args)
      { "markdown" => File.read(Rails.root.join("app/services/mcp/started_guide.md")) }
    end

    # --- Account ------------------------------------------------------------

    def list_sites(_args)
      current_month = Date.current.beginning_of_month
      counters = UsageCounter
        .where(site_id: @user.active_sites.pluck(:site_id), month: current_month)
        .pluck(:site_id, :hit_count).to_h

      @user.active_sites.map do |s|
        {
          "site_id" => s.site_id,
          "domain" => s.domain,
          "privacy_mode" => s.privacy_mode,
          "hits_this_month" => counters.fetch(s.site_id, 0).to_i,
          "plan_limit" => @user.plan_limit,
          "created_at" => s.created_at.iso8601
        }
      end
    end

    def add_site(args)
      domain = args["domain"].to_s.strip.downcase
      raise ArgumentError, "domain required" if domain.empty?

      privacy_mode = (args["privacy_mode"] || "strict").to_s
      unless Site::PRIVACY_MODES.include?(privacy_mode)
        raise ArgumentError, "privacy_mode must be one of #{Site::PRIVACY_MODES.inspect}"
      end

      if @user.active_sites.where("created_at > ?", 24.hours.ago).count >= 10
        raise RateLimitedError, "site creation rate limit reached (10/day)"
      end

      site = @user.sites.create!(domain: domain, privacy_mode: privacy_mode)

      {
        "site_id" => site.site_id,
        "domain" => site.domain,
        "privacy_mode" => site.privacy_mode,
        "tracking_snippet" => tracking_snippet(site.site_id),
        "install_instructions" =>
          "Falls du schon mit Platzhalter gearbeitet hast: einmal in deinem " \
          "Codebase suchen+ersetzen #{PLACEHOLDER_SITE_ID} → #{site.site_id}. " \
          "Dann ist das Tracking aktiv."
      }
    end

    def get_tracking_snippet(args)
      site = find_site!(args["site_id"])
      {
        "site_id" => site.site_id,
        "domain" => site.domain,
        "snippet_html" => tracking_snippet(site.site_id),
        "install_instructions" => "Einbauen vor </body>. SPA: das Script " \
          "hooked sich automatisch in history.pushState. Custom events: " \
          "window.mcpa('track', 'signup', { plan: 'pro' })."
      }
    end

    def remove_site(args)
      site = find_site!(args["site_id"])
      site.soft_delete!
      { "site_id" => site.site_id, "removed" => true }
    end

    def get_account(_args)
      {
        "email" => @user.email,
        "plan" => @user.plan,
        "total_sites" => @user.active_sites.count,
        "total_hits_this_month" => @user.hits_this_month,
        "plan_limit" => @user.plan_limit,
        "api_token_first_chars" => @user.api_token[0, 10]
      }
    end

    def regenerate_api_token(_args)
      @user.regenerate_api_token!
      base = ENV.fetch("PUBLIC_BASE_URL", "https://mcp-analytics.com")
      {
        "api_token" => @user.api_token,
        "mcp_url" => "#{base}/mcp?token=#{@user.api_token}",
        "note" => "Old token revoked. Update your MCP connector URL."
      }
    end

    # --- Analytics ----------------------------------------------------------

    def get_overview(args)
      site = find_site!(args["site_id"])
      queries(site).overview(Analytics::Period.parse(args["period"]))
    end

    def get_timeseries(args)
      site = find_site!(args["site_id"])
      metric = args.fetch("metric")
      granularity = args["granularity"] || "day"
      queries(site).timeseries(metric, Analytics::Period.parse(args["period"]), granularity: granularity)
    end

    def top_pages(args)
      site = find_site!(args["site_id"])
      queries(site).top_pages(Analytics::Period.parse(args["period"]),
                              limit: clamped_limit(args["limit"]))
    end

    def top_referrers(args)
      site = find_site!(args["site_id"])
      queries(site).top_referrers(Analytics::Period.parse(args["period"]),
                                  limit: clamped_limit(args["limit"]))
    end

    def top_sources(args)
      site = find_site!(args["site_id"])
      queries(site).top_sources(Analytics::Period.parse(args["period"]),
                                limit: clamped_limit(args["limit"]))
    end

    def breakdown(args)
      site = find_site!(args["site_id"])
      dimension = args.fetch("dimension")
      queries(site).breakdown(dimension, Analytics::Period.parse(args["period"]),
                              limit: clamped_limit(args["limit"]))
    end

    def list_events(args)
      site = find_site!(args["site_id"])
      queries(site).list_events(Analytics::Period.parse(args["period"]))
    end

    def event_details(args)
      site = find_site!(args["site_id"])
      queries(site).event_details(
        args.fetch("event_name"),
        Analytics::Period.parse(args["period"]),
        group_by_property: args["group_by_property"]
      )
    end

    def compare_periods(args)
      site = find_site!(args["site_id"])
      queries(site).compare(
        args.fetch("metric"),
        Analytics::Period.parse(args["period_a"]),
        Analytics::Period.parse(args["period_b"])
      )
    end

    # --- helpers ------------------------------------------------------------

    private

    class NotFoundError < StandardError; end
    class RateLimitedError < StandardError; end

    def find_site!(site_id)
      site_id = site_id.to_s.strip
      raise ArgumentError, "site_id required" if site_id.empty?

      site = @user.active_sites.find_by(site_id: site_id)
      raise NotFoundError, "site not found: #{site_id}" unless site
      site
    end

    def queries(site)
      Analytics::Queries.new(site)
    end

    def clamped_limit(value)
      n = (value || 10).to_i
      return 10 if n <= 0
      [n, 1000].min
    end

    def tracking_snippet(site_id)
      tracker_base = ENV.fetch("TRACKER_BASE_URL", "https://t.mcp-analytics.com")
      %Q(<script defer data-site="#{site_id}" src="#{tracker_base}/script.js"></script>)
    end

    DISPOSABLE_DOMAINS = %w[
      10minutemail.com mailinator.com guerrillamail.com tempmail.com
      throwawaymail.com yopmail.com trashmail.com temp-mail.org
      getnada.com dropmail.me
    ].freeze

    def disposable_email_domain?(email)
      domain = email.split("@", 2)[1].to_s.downcase
      DISPOSABLE_DOMAINS.include?(domain)
    end
  end
end

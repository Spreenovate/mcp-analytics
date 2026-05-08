module Mcp
  # Schemas the MCP client sees in tools/list.
  # Kept as a module-level constant so both the schema response and the
  # dispatch layer share a single source of truth for tool names.
  #
  # Each authenticated tool declares the OAuth scope required to call it
  # (`scope:` key) and whether it should be hidden from OAuth-issued
  # tokens entirely (`oauth_forbidden: true`). The `scope` key is dropped
  # from the wire response in `Mcp::Server#visible_tools` since it's an
  # internal enforcement signal, not part of the MCP schema.
  #
  # Annotation conventions (per MCP spec 2025-06-18 + Anthropic
  # directory-review checklist):
  #   - Every tool has a `title` (short human-readable name).
  #   - Read-only tools (search/get/list/fetch) carry
  #     annotations.readOnlyHint = true. They also set
  #     idempotentHint = true since re-running with the same args
  #     yields the same result, and openWorldHint = false because the
  #     tool only touches our own ClickHouse + Postgres, never an
  #     external API at call time.
  #   - Destructive tools (create/update/delete) carry
  #     annotations.destructiveHint = true. We don't claim
  #     idempotency on destructive paths — `add_site` mints a new
  #     site_id on each successful call, `regenerate_api_token`
  #     produces a fresh token each time.
  module ToolSchemas
    # MCP server is a protected resource: every /mcp request requires OAuth
    # auth (or a legacy bearer token). The controller returns 401 +
    # WWW-Authenticate before dispatch ever runs. UNAUTHENTICATED is kept
    # as an empty constant so call sites that referenced it still compile.
    UNAUTHENTICATED = [].freeze

    SCOPE_KEY = :scope
    OAUTH_FORBIDDEN_KEY = :oauth_forbidden
    INTERNAL_KEYS = [ SCOPE_KEY, OAUTH_FORBIDDEN_KEY ].freeze

    # Reusable annotation snippets — keeps the schema list scannable
    # and makes "all read tools share the same hint shape" enforceable
    # by inspection.
    READ_ANNOTATIONS = {
      readOnlyHint: true,
      idempotentHint: true,
      openWorldHint: false
    }.freeze

    DESTRUCTIVE_ANNOTATIONS = {
      readOnlyHint: false,
      destructiveHint: true,
      openWorldHint: false
    }.freeze

    AUTHENTICATED = [
      {
        name: "get_started_guide",
        title: "Getting started guide",
        description: "Markdown walkthrough of the mcp-analytics workflow: adding sites, installing the tracker, querying analytics, custom events.",
        inputSchema: { type: "object", properties: {} },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "list_sites",
        title: "List sites",
        description: "List all sites on the authenticated account. Each entry contains: site_id, domain, privacy_mode, hits_this_month (current calendar month), plan_limit, created_at.",
        inputSchema: { type: "object", properties: {} },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "add_site",
        title: "Add site",
        description: "Register a new site. privacy_mode cannot be changed later.",
        inputSchema: {
          type: "object",
          properties: {
            domain: { type: "string" },
            privacy_mode: { type: "string", enum: %w[strict balanced all], default: "strict", description: "strict (recommended): no cookies, visitor_id always 0, salt rotates daily. balanced: no cookies, daily-rotating hash, same-day visitor dedup. all: persistent cookie, cross-session tracking, you handle the consent banner." }
          },
          required: [ "domain" ]
        },
        annotations: DESTRUCTIVE_ANNOTATIONS,
        scope: Oauth::Scopes::MANAGE
      },
      {
        name: "get_tracking_snippet",
        title: "Get tracking snippet",
        description: "Return the HTML <script> snippet for a given site_id.",
        inputSchema: {
          type: "object",
          properties: { site_id: { type: "string" } },
          required: [ "site_id" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "remove_site",
        title: "Remove site",
        description: "Soft-delete a site. Historical events remain until TTL expires.",
        inputSchema: {
          type: "object",
          properties: { site_id: { type: "string" } },
          required: [ "site_id" ]
        },
        annotations: DESTRUCTIVE_ANNOTATIONS,
        scope: Oauth::Scopes::MANAGE
      },
      {
        name: "get_overview",
        title: "Period overview",
        description: "TL;DR for the period: headline metrics (pageviews, visitors, sessions, bounce rate, avg session duration) plus pageviews_change_pct vs the previous equivalent window, top page, top traffic source, bot share, and top 3 custom events. Designed so a single call answers 'how did <period> go?' without chaining other tools. Volume metrics (pageviews / visitors / sessions / bot_share) include AI-mediated human browsing (ai_user_action — Claude/ChatGPT fetching on a user's behalf); attribution metrics (top_source) count direct browser visits only because AI-mediated traffic loses original utm/referrer tags. See traffic_class_breakdown for the per-class split.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" }
          },
          required: [ "site_id" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "get_timeseries",
        title: "Time series",
        description: "Time-bucketed metric over a period. pageviews/visitors/sessions include AI-mediated human browsing (ai_user_action) — see traffic_class_breakdown to see the AI-vs-direct split.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            metric: { type: "string", enum: %w[pageviews visitors sessions] },
            period: { type: "string", default: "last_7_days" },
            granularity: { type: "string", enum: %w[hour day week], default: "day" }
          },
          required: [ "site_id", "metric" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "top_pages",
        title: "Top pages",
        description: "Most-viewed URL paths. Counts both direct browser visits and AI-mediated human browsing (ai_user_action) — see traffic_class_breakdown if you need to separate them.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" },
            limit: { type: "integer", default: 10 }
          },
          required: [ "site_id" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "top_referrers",
        title: "Top referrers",
        description: "Top referring hosts. Attribution metric — counts direct browser visits only ('user' class). AI-mediated traffic (Claude/ChatGPT fetching on a user's behalf) is excluded because the AI sets its own host as referrer or strips it; including it would inflate 'direct' or 'claude.ai' without telling you where the human attention actually came from.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" },
            limit: { type: "integer", default: 10 }
          },
          required: [ "site_id" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "top_sources",
        title: "Top traffic sources",
        description: "Top UTM source/medium/campaign combinations. Attribution metric — counts direct browser visits only ('user' class). AI-mediated traffic loses original UTM tags so it would only add noise.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" },
            limit: { type: "integer", default: 10 }
          },
          required: [ "site_id" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "breakdown",
        title: "Visit breakdown",
        description: "Breakdown of visits by browser, os, device_type, or country (country empty in MVP). Volume metric — counts include AI-mediated human browsing (ai_user_action).",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            dimension: { type: "string", enum: %w[browser os device_type country] },
            period: { type: "string", default: "last_7_days" },
            limit: { type: "integer", default: 10 }
          },
          required: [ "site_id", "dimension" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "list_events",
        title: "List events",
        description: "All event names with counts (includes 'pageview' and custom events). Volume metric — counts include AI-mediated human browsing (ai_user_action).",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" }
          },
          required: [ "site_id" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "event_details",
        title: "Event details",
        description: "Details for one event. Optionally break down by a custom property. Volume metric — counts include AI-mediated human browsing (ai_user_action).",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            event_name: { type: "string" },
            period: { type: "string", default: "last_7_days" },
            group_by_property: { type: "string" }
          },
          required: [ "site_id", "event_name" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "compare_periods",
        title: "Compare periods",
        description: "Compare a metric between two periods. Volume metric — counts include AI-mediated human browsing (ai_user_action).",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            metric: { type: "string", enum: %w[pageviews visitors sessions] },
            period_a: { type: "string" },
            period_b: { type: "string" }
          },
          required: [ "site_id", "metric", "period_a", "period_b" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "top_user_agents",
        title: "Top user agents",
        description: <<~DESC.strip,
          Top User-Agent strings with their traffic_class. Default analytics queries hide everything except real visitors; this tool surfaces the rest so you can see who is actually fetching the site. Pass traffic_class to filter to one bucket. The 8 classes (Phase 2 Cloudflare-compatible taxonomy):

          - user: real human visitor with their own browser
          - ai_user_action: live AI browse — a human is chatting with ChatGPT/Claude/Perplexity/Copilot and the assistant fetched the page on their behalf (counts as human attention, just AI-mediated)
          - ai_search: AI search-engine indexers (PerplexityBot, OAI-SearchBot, ...) — your page is a candidate answer in their index
          - ai_training: AI training crawlers (GPTBot, ClaudeBot, CCBot, Bytespider, ...) — your content lands in training data, no human is actively reading right now
          - search_index: classic search engines (Googlebot, Bingbot, Yandex, DuckDuckBot, ...)
          - social_unfurl: link-preview / social-card bots (Slackbot, facebookexternalhit, Twitterbot, LinkedInBot, ...)
          - scanner: security/uptime/perf monitoring (Censys, Pingdom, Lighthouse, headless Chrome from a cloud range, ...)
          - bot_other: recognized as a bot but not in any specific bucket, OR a UA we caught spoofing (e.g. a fake "GPTBot" coming from a random EC2 IP)

          The `humans` filter alias expands to (user, ai_user_action) — useful for "real human attention including AI-mediated".
        DESC
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" },
            limit: { type: "integer", default: 25 },
            traffic_class: {
              type: "string",
              enum: %w[user ai_user_action ai_search ai_training search_index social_unfurl scanner bot_other humans]
            }
          },
          required: [ "site_id" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "traffic_class_breakdown",
        title: "Traffic class breakdown",
        description: <<~DESC.strip,
          Hit counts and percentages by traffic_class for the period. Sorted by hits descending. Classes with zero hits are omitted (a missing class means no hits in that period, treat as zero).

          The 8 classes (Phase 2 Cloudflare-compatible taxonomy):

          - user: real human visitor with their own browser
          - ai_user_action: live AI browse — a human is chatting with ChatGPT/Claude/Perplexity/Copilot and the assistant fetched the page on their behalf. Counts as human attention, just AI-mediated.
          - ai_search: AI search-engine indexers (PerplexityBot, OAI-SearchBot) — your page is a candidate answer in their index
          - ai_training: AI training crawlers (GPTBot, ClaudeBot, CCBot, Bytespider) — your content lands in training data, no human is actively reading right now
          - search_index: classic search engines (Googlebot, Bingbot, Yandex, DuckDuckBot)
          - social_unfurl: link-preview / social-card bots (Slackbot, facebookexternalhit, Twitterbot, LinkedInBot)
          - scanner: security/uptime/perf monitoring (Censys, Pingdom, Lighthouse, headless Chrome from a cloud range)
          - bot_other: recognized as a bot but not in any specific bucket, OR a UA we caught spoofing (e.g. a fake "GPTBot" coming from a random EC2 IP)

          For "how much human traffic did I get?" sum hits where traffic_class is 'user' or 'ai_user_action'. The same union is also exposed as the 'humans' alias in top_user_agents' traffic_class filter.

          Note on consistency: get_overview's `bot_share` field uses the same human/non-human split (excludes user + ai_user_action), so the two tools agree on what counts as bot traffic.

          Note on history: rows from before Phase 2 deployed were reclassified by User-Agent only (we don't store IPs for privacy), so older data may under-report scanner-via-cloud-IP and over-attribute spoofed UAs.
        DESC
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" }
          },
          required: [ "site_id" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "top_timezones",
        title: "Top timezones",
        description: "Top IANA timezones (Europe/Berlin, America/New_York, ...) of visitors. Quasi-geo signal without IP-based lookups — captured client-side via Intl.DateTimeFormat.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" },
            limit: { type: "integer", default: 10 }
          },
          required: [ "site_id" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "top_languages",
        title: "Top languages",
        description: "Top browser languages (de-DE, en-US, ...) of visitors. From navigator.language.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" },
            limit: { type: "integer", default: 10 }
          },
          required: [ "site_id" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "color_scheme_breakdown",
        title: "Color scheme breakdown",
        description: "Share of visitors with prefers-color-scheme: dark vs light. Useful for product decisions ('should we default to dark mode?').",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" }
          },
          required: [ "site_id" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "viewport_breakdown",
        title: "Viewport breakdown",
        description: "Pageviews bucketed by viewport width: mobile_xs (<480), mobile (<768), tablet (<1024), desktop (<1440), desktop_xl (≥1440). Real usable viewport, not screen resolution.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" }
          },
          required: [ "site_id" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "engagement_overview",
        title: "Engagement overview",
        description: "Real reading time + scroll depth from the engagement beacon (fired on pagehide). Returns engaged_pages count, avg/median/p90 engagement seconds, and avg/median scroll-depth percentage. Better signal than session duration which counts inactive tabs.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" }
          },
          required: [ "site_id" ]
        },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        name: "get_account",
        title: "Account info",
        description: "Account info — email, current plan, total active sites, total_hits_this_month (across all sites), plan_limit, and api_token_first_chars (first 10 chars of the legacy API token, for identification only — not enough to authenticate).",
        inputSchema: { type: "object", properties: {} },
        annotations: READ_ANNOTATIONS,
        scope: Oauth::Scopes::READ
      },
      {
        # Hidden from OAuth-issued sessions: an OAuth client could call this
        # to extract the legacy account-wide api_token, escaping the OAuth
        # grant lifecycle (revocation, expiry, audit). Available to legacy
        # api_token sessions, where the caller already has the master token
        # and can rotate it.
        name: "regenerate_api_token",
        title: "Regenerate API token",
        description: "Invalidate the current API token and issue a new one. Returns the new MCP URL.",
        inputSchema: { type: "object", properties: {} },
        annotations: DESTRUCTIVE_ANNOTATIONS,
        scope: Oauth::Scopes::MANAGE,
        oauth_forbidden: true
      }
    ].freeze
  end
end

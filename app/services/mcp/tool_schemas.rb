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
  module ToolSchemas
    UNAUTHENTICATED = [
      {
        name: "register_account",
        description: "Start signup by emailing a verification link. Returns a pending user id and a placeholder site id you can use in code before the user has clicked the verification link.",
        inputSchema: {
          type: "object",
          properties: { email: { type: "string", description: "User's email address." } },
          required: [ "email" ]
        }
      },
      {
        name: "get_started_guide",
        description: "Markdown explanation of the full mcp-analytics signup and tracking flow, including the pre-verify placeholder workflow.",
        inputSchema: { type: "object", properties: {} }
      }
    ].freeze

    SCOPE_KEY = :scope
    OAUTH_FORBIDDEN_KEY = :oauth_forbidden
    INTERNAL_KEYS = [ SCOPE_KEY, OAUTH_FORBIDDEN_KEY ].freeze

    # The 'get_started_guide' is also useful for authed users who want a
    # refresher on tools and conventions, so it appears in both lists.
    GET_STARTED_GUIDE = UNAUTHENTICATED.last

    AUTHENTICATED = [
      GET_STARTED_GUIDE,
      {
        name: "list_sites",
        description: "List all sites on the authenticated account.",
        inputSchema: { type: "object", properties: {} },
        scope: Oauth::Scopes::READ
      },
      {
        name: "add_site",
        description: "Register a new site. privacy_mode cannot be changed later.",
        inputSchema: {
          type: "object",
          properties: {
            domain: { type: "string" },
            privacy_mode: { type: "string", enum: %w[strict default all], default: "strict" }
          },
          required: [ "domain" ]
        },
        scope: Oauth::Scopes::MANAGE
      },
      {
        name: "get_tracking_snippet",
        description: "Return the HTML <script> snippet for a given site_id.",
        inputSchema: {
          type: "object",
          properties: { site_id: { type: "string" } },
          required: [ "site_id" ]
        },
        scope: Oauth::Scopes::READ
      },
      {
        name: "remove_site",
        description: "Soft-delete a site. Historical events remain until TTL expires.",
        inputSchema: {
          type: "object",
          properties: { site_id: { type: "string" } },
          required: [ "site_id" ]
        },
        scope: Oauth::Scopes::MANAGE
      },
      {
        name: "get_overview",
        description: "TL;DR for the period: headline metrics (pageviews, visitors, sessions, bounce rate, avg session duration) plus pageviews_change_pct vs the previous equivalent window, top page, top traffic source, bot share, and top 3 custom events. Designed so a single call answers 'how did <period> go?' without chaining other tools.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" }
          },
          required: [ "site_id" ]
        },
        scope: Oauth::Scopes::READ
      },
      {
        name: "get_timeseries",
        description: "Time-bucketed metric over a period.",
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
        scope: Oauth::Scopes::READ
      },
      {
        name: "top_pages",
        description: "Most-viewed URL paths.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" },
            limit: { type: "integer", default: 10 }
          },
          required: [ "site_id" ]
        },
        scope: Oauth::Scopes::READ
      },
      {
        name: "top_referrers",
        description: "Top referring hosts.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" },
            limit: { type: "integer", default: 10 }
          },
          required: [ "site_id" ]
        },
        scope: Oauth::Scopes::READ
      },
      {
        name: "top_sources",
        description: "Top UTM source/medium/campaign combinations.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" },
            limit: { type: "integer", default: 10 }
          },
          required: [ "site_id" ]
        },
        scope: Oauth::Scopes::READ
      },
      {
        name: "breakdown",
        description: "Breakdown of visits by browser, os, device_type, or country (country empty in MVP).",
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
        scope: Oauth::Scopes::READ
      },
      {
        name: "list_events",
        description: "All event names with counts (includes 'pageview' and custom events).",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" }
          },
          required: [ "site_id" ]
        },
        scope: Oauth::Scopes::READ
      },
      {
        name: "event_details",
        description: "Details for one event. Optionally break down by a custom property.",
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
        scope: Oauth::Scopes::READ
      },
      {
        name: "compare_periods",
        description: "Compare a metric between two periods.",
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
        scope: Oauth::Scopes::READ
      },
      {
        name: "top_user_agents",
        description: "Top User-Agent strings with their traffic_class (user / bot). Default analytics queries hide bots; this surfaces them so you can see AI agents (ChatGPT-User, Claude-User, GPTBot, ...), search indexers (Googlebot), social unfurlers (Slackbot), and scanners. Pass traffic_class to filter to one bucket.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" },
            limit: { type: "integer", default: 25 },
            traffic_class: { type: "string", enum: %w[user bot] }
          },
          required: [ "site_id" ]
        },
        scope: Oauth::Scopes::READ
      },
      {
        name: "traffic_class_breakdown",
        description: "Hit counts and percentages by traffic_class (user vs bot) for the period.",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" }
          },
          required: [ "site_id" ]
        },
        scope: Oauth::Scopes::READ
      },
      {
        name: "get_account",
        description: "Account info — email, plan, usage.",
        inputSchema: { type: "object", properties: {} },
        scope: Oauth::Scopes::READ
      },
      {
        # Hidden from OAuth-issued sessions: an OAuth client could call this
        # to extract the legacy account-wide api_token, escaping the OAuth
        # grant lifecycle (revocation, expiry, audit). Available to legacy
        # api_token sessions, where the caller already has the master token
        # and can rotate it.
        name: "regenerate_api_token",
        description: "Invalidate the current API token and issue a new one. Returns the new MCP URL.",
        inputSchema: { type: "object", properties: {} },
        scope: Oauth::Scopes::MANAGE,
        oauth_forbidden: true
      }
    ].freeze
  end
end

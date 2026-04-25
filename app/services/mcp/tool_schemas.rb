module Mcp
  # Schemas the MCP client sees in tools/list.
  # Kept as a module-level constant so both the schema response and the
  # dispatch layer share a single source of truth for tool names.
  module ToolSchemas
    UNAUTHENTICATED = [
      {
        name: "register_account",
        description: "Start signup by emailing a verification link. Returns a pending user id and a placeholder site id you can use in code before the user has clicked the verification link.",
        inputSchema: {
          type: "object",
          properties: { email: { type: "string", description: "User's email address." } },
          required: ["email"]
        }
      },
      {
        name: "get_started_guide",
        description: "Markdown explanation of the full mcp-analytics signup and tracking flow, including the pre-verify placeholder workflow.",
        inputSchema: { type: "object", properties: {} }
      }
    ].freeze

    # The 'get_started_guide' is also useful for authed users who want a
    # refresher on tools and conventions, so it appears in both lists.
    GET_STARTED_GUIDE = UNAUTHENTICATED.last

    AUTHENTICATED = [
      GET_STARTED_GUIDE,
      {
        name: "list_sites",
        description: "List all sites on the authenticated account.",
        inputSchema: { type: "object", properties: {} }
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
          required: ["domain"]
        }
      },
      {
        name: "get_tracking_snippet",
        description: "Return the HTML <script> snippet for a given site_id.",
        inputSchema: {
          type: "object",
          properties: { site_id: { type: "string" } },
          required: ["site_id"]
        }
      },
      {
        name: "remove_site",
        description: "Soft-delete a site. Historical events remain until TTL expires.",
        inputSchema: {
          type: "object",
          properties: { site_id: { type: "string" } },
          required: ["site_id"]
        }
      },
      {
        name: "get_overview",
        description: "Key metrics (pageviews, visitors, sessions, bounce rate, avg session duration).",
        inputSchema: {
          type: "object",
          properties: {
            site_id: { type: "string" },
            period: { type: "string", default: "last_7_days" }
          },
          required: ["site_id"]
        }
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
          required: ["site_id", "metric"]
        }
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
          required: ["site_id"]
        }
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
          required: ["site_id"]
        }
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
          required: ["site_id"]
        }
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
          required: ["site_id", "dimension"]
        }
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
          required: ["site_id"]
        }
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
          required: ["site_id", "event_name"]
        }
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
          required: ["site_id", "metric", "period_a", "period_b"]
        }
      },
      {
        name: "get_account",
        description: "Account info — email, plan, usage.",
        inputSchema: { type: "object", properties: {} }
      },
      {
        name: "regenerate_api_token",
        description: "Invalidate the current API token and issue a new one. Returns the new MCP URL.",
        inputSchema: { type: "object", properties: {} }
      }
    ].freeze
  end
end

Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"

  # MCP JSON-RPC endpoint. POST for actual calls; GET returns a short info blob.
  post "/mcp" => "mcp#dispatch_rpc"
  get  "/mcp" => "mcp#info"

  # Landing-page email signup.
  post "/signup"       => "signups#create", as: :signup
  get  "/signup/check" => "signups#check",  as: :signup_check

  # Verification link from signup email. GET shows a confirmation page
  # (no state change — defends against `<img src=>` style auth-CSRF);
  # POST does the actual user-creation / sign-in / consent-redirect.
  get  "/verify/:token" => "verifications#show",    as: :verify
  post "/verify/:token" => "verifications#confirm", as: :verify_confirm

  # OAuth 2.1 (RFC 6749 + RFC 7636 + RFC 7591 + RFC 9728)
  get  "/.well-known/oauth-authorization-server" => "oauth/discovery#authorization_server"
  get  "/.well-known/oauth-protected-resource"   => "oauth/discovery#protected_resource"
  # Path-aware variant per RFC 8414 §3.1 / RFC 9728 §3.1: clients that
  # know the resource path query the suffixed form first. ChatGPT's MCP
  # custom-connector flow specifically does this (per OpenAI community
  # report — fails with "Failed to resolve OAuth client" if the suffixed
  # path 404s, doesn't fall back to the root-level path). Both serve
  # the same JSON for our single resource at /mcp.
  get  "/.well-known/oauth-authorization-server/mcp" => "oauth/discovery#authorization_server"
  get  "/.well-known/oauth-protected-resource/mcp"   => "oauth/discovery#protected_resource"
  post "/oauth/register" => "oauth/clients#create",        as: :oauth_register
  get  "/oauth/authorize" => "oauth/authorizations#new",   as: :oauth_authorize
  post "/oauth/authorize/start" => "oauth/authorizations#start", as: :oauth_authorize_start
  get  "/oauth/consent/:request_token" => "oauth/authorizations#show", as: :oauth_consent
  post "/oauth/consent/:request_token" => "oauth/authorizations#decide", as: :oauth_consent_decide
  post "/oauth/token" => "oauth/tokens#create",            as: :oauth_token
  post "/oauth/revoke" => "oauth/revocations#create",      as: :oauth_revoke

  # CORS preflight: claude.ai's MCP custom-connector flow runs the token
  # exchange (and likely /mcp itself) from the browser, so it sends an
  # OPTIONS preflight first. Without these no-op routes Rails returns
  # 404 + no CORS headers and the real POST is silently blocked by the
  # browser. See claude-ai-mcp issues #46 / #163 / #215.
  match "/.well-known/oauth-authorization-server" => "oauth/discovery#preflight",   via: :options
  match "/.well-known/oauth-protected-resource"   => "oauth/discovery#preflight",   via: :options
  match "/.well-known/oauth-authorization-server/mcp" => "oauth/discovery#preflight", via: :options
  match "/.well-known/oauth-protected-resource/mcp"   => "oauth/discovery#preflight", via: :options
  match "/oauth/register" => "oauth/clients#preflight",       via: :options
  match "/oauth/token"    => "oauth/tokens#preflight",        via: :options
  match "/oauth/revoke"   => "oauth/revocations#preflight",   via: :options
  match "/mcp"            => "mcp#preflight",                 via: :options

  # Self-service settings (web UI). Session is established by clicking
  # the verify-link from a fresh signup-form submission.
  get  "/settings"                            => "settings#show",             as: :settings
  post "/settings/connectors/:id/revoke"      => "settings#revoke_connector", as: :revoke_connector
  post "/settings/sign_out"                   => "settings#sign_out",         as: :settings_sign_out

  # Docs (for humans — agents just need the MCP URL).
  get "/docs" => "pages#docs", as: :docs

  # Content marketing surfaces (CONTENT_MARKETING.md). All public, all
  # indexable, sitemap-listed. Blog + comparisons are markdown-backed
  # (see BlogPost / Comparison models); /mcp/tools/* is generated from
  # the same schema list the MCP server itself uses.
  #
  # English lives at the bare path (/blog, /vs); German is /de-prefixed.
  # No Rails I18n setup — locale is a controller param, not a session
  # state. hreflang tags are emitted by the views so each post points to
  # its translated counterpart if one exists.
  slug_constraint = { slug: /[a-z0-9][a-z0-9\-]*/ }

  get "/blog"           => "blogs#index", as: :blog,          defaults: { locale: "en" }
  get "/blog/:slug"     => "blogs#show",  as: :blog_post,     defaults: { locale: "en" }, constraints: slug_constraint
  get "/de/blog"        => "blogs#index", as: :de_blog,       defaults: { locale: "de" }
  get "/de/blog/:slug"  => "blogs#show",  as: :de_blog_post,  defaults: { locale: "de" }, constraints: slug_constraint

  get "/vs"             => "comparisons#index", as: :comparisons,    defaults: { locale: "en" }
  get "/vs/:slug"       => "comparisons#show",  as: :comparison,     defaults: { locale: "en" }, constraints: slug_constraint
  get "/de/vs"          => "comparisons#index", as: :de_comparisons, defaults: { locale: "de" }
  get "/de/vs/:slug"    => "comparisons#show",  as: :de_comparison,  defaults: { locale: "de" }, constraints: slug_constraint

  # /mcp/tools/:slug — NOT to be confused with /mcp (JSON-RPC). The
  # routing is unambiguous because /mcp is exact-match on the RPC
  # controller while /mcp/tools/* is a different prefix.
  get "/mcp/tools"        => "mcp_tools#index", as: :mcp_tools
  get "/mcp/tools/:slug"  => "mcp_tools#show",  as: :mcp_tool, constraints: slug_constraint

  # AI-crawler observability page — moat content. Static shell with
  # N=1 demo pre-launch; swap to live ClickHouse aggregates once we
  # have ≥50 Pro customers (see CONTENT_MARKETING.md §C).
  get "/ai-crawler-index" => "ai_crawler_index#show", as: :ai_crawler_index

  # Dynamic sitemap — replaces the static public/sitemap.xml so blog
  # posts and comparison pages get picked up automatically.
  get "/sitemap.xml" => "sitemaps#show", as: :sitemap

  # Legal pages.
  get "/terms"   => "pages#terms",   as: :terms
  get "/privacy" => "pages#privacy", as: :privacy
end

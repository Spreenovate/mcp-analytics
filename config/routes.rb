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

  # Legal pages.
  get "/terms"   => "pages#terms",   as: :terms
  get "/privacy" => "pages#privacy", as: :privacy
end

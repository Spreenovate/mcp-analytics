Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"

  # MCP JSON-RPC endpoint. POST for actual calls; GET returns a short info blob.
  post "/mcp" => "mcp#dispatch_rpc"
  get  "/mcp" => "mcp#info"

  # Landing-page email signup.
  post "/signup"       => "signups#create", as: :signup
  get  "/signup/check" => "signups#check",  as: :signup_check

  # Verification link from signup email.
  get "/verify/:token" => "verifications#show", as: :verify

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

  # Legal pages.
  get "/terms"   => "pages#terms",   as: :terms
  get "/privacy" => "pages#privacy", as: :privacy
end

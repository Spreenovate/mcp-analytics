Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  root "pages#home"

  # MCP JSON-RPC endpoint. POST for actual calls; GET returns a short info blob.
  post "/mcp" => "mcp#dispatch_rpc"
  get  "/mcp" => "mcp#info"

  # Verification link from signup email.
  get "/verify/:token" => "verifications#show", as: :verify

  # Magic-link sign-in for /settings.
  get    "/login"      => "sessions#new",       as: :login
  post   "/magic-link" => "sessions#create",    as: :magic_link
  get    "/auth/:token" => "sessions#show",     as: :auth
  delete "/logout"     => "sessions#destroy",   as: :logout

  # Settings (web UI).
  get    "/settings"                     => "settings#show",            as: :settings
  post   "/settings/regenerate-token"    => "settings#regenerate_token", as: :regenerate_token_settings
  delete "/settings/delete-account"      => "settings#destroy_account",  as: :destroy_account_settings
end

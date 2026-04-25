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

  # Legal pages.
  get "/terms"   => "pages#terms",   as: :terms
  get "/privacy" => "pages#privacy", as: :privacy
end

# Pin the session-cookie security flags so a future contributor can't
# silently weaken them. Cookie carries the Settings-UI auth assertion
# (see SettingsSession concern), so the contract here matters.
#
# Notes:
#   secure:    only HTTPS cookies in production. force_ssl in
#              production.rb covers HSTS too.
#   httponly:  JavaScript can't read the cookie -> XSS can't steal it.
#   same_site: :lax allows the inbound nav from email clients (verify
#              link) which is the whole point. :strict would break that.
Rails.application.config.session_store :cookie_store,
  key: "_mcpa_session",
  secure: Rails.env.production?,
  httponly: true,
  same_site: :lax

# Application-wide Content Security Policy.
#
# The big win is `script-src :self`: zero inline scripts in production
# means an HTML-injection-style XSS can't execute JavaScript. All
# page-specific scripts live in app/assets/javascripts/ and are
# referenced via javascript_include_tag.
#
# `style-src` keeps :unsafe_inline because the brutalist views embed
# their own <style> blocks per page. CSS-injection XSS is materially
# less dangerous than JS-injection (no token exfiltration without
# scripted side channels), and refactoring every <style> block to an
# external sheet would balloon the diff for marginal gain.
#
# Fonts & font-CSS load from fonts.googleapis.com / fonts.gstatic.com,
# both pinned to https.
#
# The dogfooding tracker (mcp-analytics tracking its own site) loads
# from t.mcp-analytics.com in production — different origin from the
# Rails host, so it must be allowlisted explicitly under script-src.
# The host is taken from TRACKER_BASE_URL so CSP and the layout stay
# in lockstep.
Rails.application.configure do
  tracker_origin = ENV.fetch("TRACKER_BASE_URL", "https://t.mcp-analytics.com")

  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.script_src      :self, tracker_origin
    policy.style_src       :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.img_src         :self, :https, :data
    policy.font_src        :self, :https, :data
    policy.connect_src     :self, "https://fonts.googleapis.com", "https://fonts.gstatic.com"
    # Same-origin only. OAuth redirects to native schemes (claude://,
    # cursor://) happen via 302 from `redirect_to`, NOT form submission,
    # so they don't pass through `form-action`. Browsers don't enforce
    # form-action on Location: headers.
    policy.form_action     :self
    policy.frame_ancestors :none
    policy.base_uri        :self
    policy.object_src      :none
  end
end

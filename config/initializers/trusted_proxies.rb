# Without an explicit trusted-proxies list, Rails honours `X-Forwarded-For`
# from any source. That makes IP-based rate-limits (oauth-authorize,
# oauth-token, oauth-revoke, oauth-dcr, signup) trivially bypassable: an
# attacker rotates the spoofed XFF value and resets the bucket each
# request.
#
# Production runs behind kamal-proxy on the same host, so the only proxy
# we should trust is loopback. Public CDN/Cloudflare ranges deliberately
# NOT included — if we add a CDN later, list its egress ranges here
# explicitly.
Rails.application.config.action_dispatch.trusted_proxies = [
  IPAddr.new("127.0.0.0/8"),    # IPv4 loopback (kamal-proxy)
  IPAddr.new("::1"),             # IPv6 loopback
  IPAddr.new("10.0.0.0/8"),      # RFC 1918 private (Docker bridge networks)
  IPAddr.new("172.16.0.0/12"),   # RFC 1918 private (Docker default)
  IPAddr.new("192.168.0.0/16"),  # RFC 1918 private
  IPAddr.new("fc00::/7"),        # RFC 4193 IPv6 ULA (Docker IPv6 dual-stack)
  IPAddr.new("fe80::/10")        # IPv6 link-local
]

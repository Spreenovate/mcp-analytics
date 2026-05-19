---
title: "MCP OAuth: Every Bug We Hit Shipping a Remote MCP Server to Claude and ChatGPT"
description: "Six months of building OAuth 2.1 for a remote MCP server. The 302 vs 303 bug. Lowercase bearer. Origin: null. CSP form-action. The /mcp suffix discovery quirk. Every quirk that made our connector silently die."
slug: mcp-oauth-deep-dive
date: 2026-05-19
---

Long-form companion to our [Claude MCP setup guide](/blog/claude-mcp-setup), for people building their own remote MCP server. Documents, in painful detail, every OAuth-related bug we hit shipping `mcp-analytics.com/mcp` to production, why each one presented as "the connector silently fails", and how we fixed each.

We've contributed several of these findings back to GitHub issues on the spec and client repos. Bugs still open as of May 2026 are noted as such.

If you're a user trying to *use* an MCP server: read the [setup guide](/blog/claude-mcp-setup) instead. This article is for server implementers.

## Why OAuth at all (when bearer tokens work)?

Three reasons remote MCP servers in 2026 should support OAuth 2.1 as the primary auth path:

1. **Anthropic's MCP directory requirements.** To be listed in Claude's official connector catalog, OAuth 2.1 with PKCE is mandatory. Bearer tokens are not accepted as the primary mechanism.
2. **ChatGPT custom connectors require OAuth.** ChatGPT's MCP custom connector flow is OAuth-only. No Bearer token shortcut exists on that platform.
3. **Revocation, scope separation, audit logs.** Bearer tokens have none of these by default. A leaked token is valid forever unless you've built the rotation infrastructure yourself. OAuth gives you scope-bound access tokens with per-client revocation built into the spec.

We support all three auth methods (OAuth Bearer, legacy Bearer, legacy `?token=` query param), but OAuth is the path that gets you into both major clients.

## Build the spec-compliant server first, then add the quirk patches

A useful framing: the OAuth 2.1 plus RFC 7591 (Dynamic Client Registration) plus RFC 8707 (audience-binding) plus RFC 9728 (Protected Resource Metadata) spec stack is well-defined. Implement it correctly and you have a *correct* server. You won't have a *working* one, because the client implementations have known deviations from the spec. Every patch below is a workaround for a client quirk, not for a spec ambiguity.

Reference implementations worth reading before you start:

- **Cloudflare's `workers-oauth-provider`**: RFC-compliant, every quirk pre-fixed. The closest thing to a canonical implementation.
- **Sentry's MCP server**: open-source, has gone through the directory submission process.
- **Linear's MCP server**: closed source but well-respected. Their public statements describe the same quirks we're about to list.

If your stack is Rails (like ours), Python+FastAPI, or Node+Express, you'll write the OAuth flow from scratch but the client behavior you're targeting is the same.

## Quirk 1: claude.ai expects 302, not 303

**Symptom**: OAuth flow seems to complete (the consent screen returns successfully) but the connector ends up with 0 tools and you can't tell why.

**Cause**: Your consent endpoint's POST handler does `redirect_to(client_redirect_uri, status: :see_other)` (HTTP 303). claude.ai's MCP custom connector parser specifically handles 302 (HTTP "Found") differently from 303 ("See Other") in the post-consent redirect step. Both are spec-valid in RFC 6749 §4.1.2 (the spec uses "redirect" generically), but the parser treats only 302 correctly.

**Fix**: explicitly return 302:

```ruby
# Rails:
redirect_to(client_redirect_uri, status: :found)  # 302, NOT :see_other (303)
```

**Reference**: [claude-ai-mcp #215](https://github.com/anthropics/claude-ai-mcp/issues/215). Still open as of May 2026.

## Quirk 2: Lowercase `"bearer"` in `token_type`

**Symptom**: Token exchange completes (200 OK from `/oauth/token`), but subsequent `Authorization: Bearer …` calls on the MCP endpoint return 401 from the client side without ever reaching your server.

**Cause**: Some strict clients reject `"token_type": "Bearer"` (capital B) and accept only `"token_type": "bearer"` (lowercase). RFC 6749 §5.1 says the type is case-insensitive *for the client to parse* but doesn't bind the server's casing. In practice, strict implementations have rejected capital.

**Fix**: emit lowercase:

```ruby
render json: {
  access_token: token.access_token,
  token_type: "bearer",     # lowercase, NOT "Bearer"
  expires_in: 3600,
  scope: token.scope_string
}
```

This is also what Cloudflare's reference implementation does. The capital-B form is technically RFC-compliant but real-world incompatible.

## Quirk 3: No `iss` parameter in the auth-response redirect

**Symptom**: Browser-based clients silently fail to complete the OAuth flow. Server logs show the consent POST succeeded and a redirect was issued, but the client never calls `/oauth/token`.

**Cause**: You followed RFC 9207 and added an `iss` parameter to the authorization-response redirect URL (e.g. `?code=…&state=…&iss=https://your-server.com`). claude.ai's frontend rejects the redirect when `iss` is present. Likely because their post-redirect validation step fails, but the failure is silent and the flow just dies.

**Fix**: drop the `iss` param. Cloudflare's reference implementation doesn't include it either. RFC 9207 is technically a SHOULD recommendation. For now, ignore it.

```ruby
# Build the redirect URL WITHOUT iss:
redirect_params = { code: code, state: state }  # NOT { iss: issuer_url, ... }
```

**Reference**: behavior reproduced in [modelcontextprotocol #2157](https://github.com/modelcontextprotocol/modelcontextprotocol/issues/2157).

## Quirk 4: `grant_types` MUST include `"refresh_token"` in the DCR response

**Symptom**: Some clients refuse to use your server entirely after Dynamic Client Registration. Connector creation never completes.

**Cause**: Your DCR (Dynamic Client Registration, RFC 7591) response declares `grant_types: ["authorization_code"]` only. Strict clients infer "no refresh-token support" and decide your server is incompatible with their session model, then skip the entire OAuth flow.

**Fix**: include `refresh_token` in the grant_types array, even if your refresh-token implementation is basic:

```ruby
render json: {
  client_id: client.client_id,
  client_secret: client.client_secret,
  grant_types: ["authorization_code", "refresh_token"],  # both
  response_types: ["code"],
  token_endpoint_auth_method: "client_secret_post",
  redirect_uris: client.redirect_uris,
  # ...
}
```

## Quirk 5: CORS preflights on EVERY OAuth endpoint

**Symptom**: Browser-based clients (claude.ai, chatgpt.com) silently fail to complete *any* OAuth or MCP operation. Server logs show *no* request at all. Not even an attempt.

**Cause**: claude.ai's and ChatGPT's MCP custom-connector flows run from the browser using `fetch()`. Modern browsers send an OPTIONS preflight before any non-simple cross-origin POST. If your server returns 404 on OPTIONS (because you only declared POST routes), the browser silently aborts the real request. Your server never sees it. You have no log line to debug from, and the connector status reads as a generic failure.

**Fix**: declare OPTIONS responders on every cross-origin OAuth and MCP endpoint:

```ruby
# config/routes.rb:
match "/.well-known/oauth-authorization-server" => "oauth/discovery#preflight", via: :options
match "/.well-known/oauth-protected-resource"   => "oauth/discovery#preflight", via: :options
match "/.well-known/oauth-authorization-server/mcp" => "oauth/discovery#preflight", via: :options
match "/.well-known/oauth-protected-resource/mcp"   => "oauth/discovery#preflight", via: :options
match "/oauth/register" => "oauth/clients#preflight",     via: :options
match "/oauth/token"    => "oauth/tokens#preflight",      via: :options
match "/oauth/revoke"   => "oauth/revocations#preflight", via: :options
match "/mcp"            => "mcp#preflight",                via: :options
```

The preflight handler returns:

```
HTTP/1.1 204 No Content
Access-Control-Allow-Origin: https://claude.ai
Access-Control-Allow-Methods: POST, GET
Access-Control-Allow-Headers: Authorization, Content-Type, MCP-Session-ID
Access-Control-Max-Age: 86400
```

Be specific about the allowed origin (a list of `https://claude.ai`, `https://chatgpt.com`, `https://cursor.com`, etc.) rather than `*`, especially for endpoints that may have `Authorization` headers. The spec forbids `Access-Control-Allow-Origin: *` with `Allow-Credentials: true`.

## Quirk 6: ChatGPT's `/.well-known/oauth-protected-resource/mcp` suffix

**Symptom**: ChatGPT's MCP custom connector creation fails with "Failed to resolve OAuth client" immediately after URL entry.

**Cause**: ChatGPT's flow tries the path-aware OAuth-protected-resource discovery (`/.well-known/oauth-protected-resource/mcp`, the resource path suffix per RFC 9728 §3.1) *first* and doesn't fall back to the root-level `/.well-known/oauth-protected-resource`. If only the root path responds, the connector aborts.

**Fix**: serve both:

```ruby
# config/routes.rb:
get "/.well-known/oauth-protected-resource"     => "oauth/discovery#protected_resource"
get "/.well-known/oauth-protected-resource/mcp" => "oauth/discovery#protected_resource"
```

Both return the same JSON body: `{ resource: "https://your-server.com/mcp", authorization_servers: [...] }`. The duplicate route is cheap; the breakage cost is high.

## Quirk 7: `Referrer-Policy: no-referrer` breaks same-origin CSRF on the consent page

**Symptom**: Users click "Approve" on your OAuth consent screen and nothing visibly happens. Browser inspector shows a 422 InvalidAuthenticityToken on the POST, or the redirect never fires.

**Cause**: You're emitting `Referrer-Policy: no-referrer` on the consent page (good hygiene for credential pages). Modern Chromium and Safari 18+ under that policy send `Origin: null` even on *same-origin* form POSTs. Rails-style origin-checked CSRF then sees `null != base_url` and rejects.

**Fix**: use `Referrer-Policy: same-origin` (not `no-referrer`) on consent pages and any page with a same-origin form POST. Same-origin still strips Referer when navigating cross-origin (so the consent URL doesn't leak to claude.ai), but lets same-origin form POSTs carry a proper Origin.

Set it in three places consistently:

1. Response header in the controller: `response.set_header("Referrer-Policy", "same-origin")`
2. `<meta name="referrer" content="same-origin">` in the page's `<head>`
3. (And check `form-action` in CSP, see Quirk 8.)

If you only fix one of the three layers, whatever the page-level meta tag or response header says wins for the next form POST, and you keep seeing Origin: null.

## Quirk 8: CSP `form-action` blocks the cross-origin OAuth redirect

**Symptom**: Consent POST goes through (no 422), but the 302 redirect back to the OAuth client (`https://claude.ai/api/mcp/auth_callback`) is *blocked silently by the browser*. The console shows "Refused to load … because it does not appear in the form-action directive". claude.ai never receives the authorization code.

**Cause**: CSP3 §6.4 says `form-action` covers "navigations from form-submission, including redirects." So your global CSP `form-action 'self'` (a perfectly sensible default) blocks the cross-origin redirect that OAuth requires.

**Fix**: scope a relaxed `form-action` to the consent page only:

```ruby
# app/controllers/oauth/authorizations_controller.rb:
content_security_policy(only: [:show, :decide]) do |policy|
  policy.form_action :self, :https
end
```

The relaxation is scoped to the OAuth consent show/decide actions, not site-wide. You allow `https:` (any HTTPS origin) rather than naming claude.ai/chatgpt.com explicitly, since you don't always know the client in advance with Dynamic Client Registration.

## Quirk 9: Audience-binding (RFC 8707), get the syntax right

**Symptom**: More subtle. Audience-binding is *required* by the spec for MCP OAuth, but some clients send the `resource` parameter as a single string and others as a JSON array.

**Cause**: RFC 8707 says `resource` can repeat. claude.ai sends it as repeated query params (`?resource=https://...&resource=https://...`). Some custom clients send a single comma-separated value. Some send a JSON-stringified array.

**Fix**: parse all three forms when validating the audience-binding:

```ruby
def parsed_resource_params
  raw = params[:resource]
  case raw
  when nil then []
  when String then raw.split(",").map(&:strip)
  when Array then raw
  end
end
```

Then validate each against your canonical resource URL (`https://your-server.com/mcp`) and reject if none match.

## Quirk 10: Scopes need to be discoverable AND requested explicitly

**Symptom**: OAuth completes, tools list loads, but write tools (like `add_site`) return 403 on call.

**Cause**: Many MCP servers split `read` from `manage` scope. The client may request only `read` if it doesn't know `manage` exists. Or the client may not pass `scope` at all, and you defaulted to the narrow scope.

**Fix**: declare both scopes in your `oauth-authorization-server` metadata:

```json
{
  "issuer": "https://your-server.com",
  "authorization_endpoint": "https://your-server.com/oauth/authorize",
  "token_endpoint": "https://your-server.com/oauth/token",
  "scopes_supported": ["analytics:read", "analytics:manage"],
  "response_types_supported": ["code"],
  "grant_types_supported": ["authorization_code", "refresh_token"],
  "code_challenge_methods_supported": ["S256"]
}
```

And in your consent screen, present BOTH scopes as checkboxes (default both checked), so users opt into the union by default. Otherwise the client requests narrow scope, the user doesn't realize they're losing write capability, and they hit 403 on every write tool a week later.

## Quirk 11: Refresh-token rotation has implementation traps

**Symptom**: Long-lived sessions work for ~24 hours, then the connector silently breaks. Re-adding it fixes for another 24 hours.

**Cause**: Your access tokens expire after some duration (60 minutes is common). The client requests a refresh-token exchange. If your refresh-token implementation is buggy (e.g. you invalidate the old refresh token *before* successfully issuing the new one, and the response is then dropped/retried), the client ends up with neither valid token and the next call fails.

**Fix**: implement refresh-token rotation atomically. The old refresh token MUST remain valid until the new one is confirmed delivered. If your DB allows it, use a transaction wrapping "issue new, invalidate old" so both succeed or neither does.

A simpler approach we recommend: emit a 7-day access token at first, with refresh-token rotation as a secondary loop. Most strict clients don't actually exercise refresh-token rotation aggressively. Long access-tokens dramatically reduce the cross-section of bugs.

## What we won't cover (out of scope here)

- **MCP protocol details** beyond OAuth. See the [Claude MCP setup guide](/blog/claude-mcp-setup) for the user-facing side and [modelcontextprotocol.io](https://modelcontextprotocol.io) for the spec.
- **Specific framework migrations** (Rails to Sinatra, Express to Fastify). Patterns transfer; specifics don't.
- **PKCE deep-dive**. PKCE is straightforward and largely problem-free. Implement it per RFC 7636 with S256, move on.

## Sanity-check curl commands

Three commands that exercise the full flow without a real client. Useful for regression testing:

```bash
# 1. Discovery
curl -s https://your-server.com/.well-known/oauth-authorization-server | jq
curl -s https://your-server.com/.well-known/oauth-protected-resource/mcp | jq

# 2. DCR (register a client)
curl -s -X POST https://your-server.com/oauth/register \
  -H 'Content-Type: application/json' \
  -d '{"client_name":"test-client","redirect_uris":["https://claude.ai/api/mcp/auth_callback"]}'

# 3. Token exchange (simulated, assuming you've got a real authorization code)
curl -s -X POST https://your-server.com/oauth/token \
  -d 'grant_type=authorization_code' \
  -d 'code=AUTH_CODE_FROM_REDIRECT' \
  -d 'client_id=CLIENT_ID_FROM_DCR' \
  -d 'client_secret=CLIENT_SECRET_FROM_DCR' \
  -d 'redirect_uri=https://claude.ai/api/mcp/auth_callback' \
  -d 'code_verifier=PKCE_VERIFIER' \
  -d 'resource=https://your-server.com/mcp'
```

If all three return spec-compliant JSON, your server is *spec-correct*. Whether it's *client-compatible* is the question this post answered.

## Final advice

1. **Match the Cloudflare reference implementation byte-for-byte** where you can. They've debugged every one of these. Diverging from them is taking on risk.
2. **Test in actual Claude Desktop, ChatGPT, and Cursor before you ship.** Each client surfaces different bugs. Passing all three is a much stronger signal than passing RFC compliance.
3. **Log everything during the connector setup flow**. The OAuth dance has many steps. When something fails silently in the client UI, your server logs are the only place to see *where* it died.
4. **Don't try to be elegant**. Add the suffix-discovery duplicate, drop the `iss` parameter, lowercase the bearer. The spec is permissive; the clients are not.

We've shipped to production with these patches and the connector survives both Claude's and ChatGPT's directory acceptance tests. If you're building something similar and run into a bug we didn't cover here, [email us](mailto:hello@mcp-analytics.com). We'll add it to this post.

Want to see the full source in context? Our internal [CLAUDE.md](https://github.com/Spreenovate/mcp-analytics) tracks every one of these as it was discovered, with commit hashes and file references.

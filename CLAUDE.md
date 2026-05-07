# CLAUDE.md — Project-specific lessons

Project-local conventions, gotchas, and commands that bit us in past sessions and aren't obvious from reading the code. Keep entries self-contained, with the **Why** so future-you can judge edge cases.

## Gotchas

### CSP `form-action` is enforced on cross-origin redirects from form POSTs

The `Refused to load … because it does not appear in the form-action directive` console message in Safari/Chromium is real and applies to **server-side 302 redirects from form-POST responses**, not just the form's own `action=` attribute. CSP3 §6.4: form-action covers "navigations from form-submission, INCLUDING redirects."

**Why this matters here:** the OAuth consent flow POSTs `/oauth/consent/:token` and 302s to the OAuth client's `redirect_uri` (e.g. `https://claude.ai/api/mcp/auth_callback`). The global policy in [content_security_policy.rb](config/initializers/content_security_policy.rb) sets `form-action 'self'` — so without the per-controller relaxation in [oauth/authorizations_controller.rb](app/controllers/oauth/authorizations_controller.rb), the consent button does nothing visible (the redirect is browser-blocked, claude.ai never sees the code, OAuth flow dies silently).

**How to apply:** anytime you add a controller that POST → 302s cross-origin (OAuth, SAML, payment provider returns), add a scoped `content_security_policy(only: [...])` block on the page that *contains the form* (not just the action endpoint — the check runs against the form-page's policy). Allow `:self :https` minimum, narrower if you can pin the destination origin.

### `Referrer-Policy: no-referrer` breaks Rails CSRF on same-origin form POSTs

Modern Chromium (and Safari 18) under `Referrer-Policy: no-referrer` send `Origin: null` even on same-origin form POSTs. Rails' origin-based CSRF check then sees `null != base_url` → 422 InvalidAuthenticityToken.

**Why this matters here:** burned us once on `/verify/:token` POST (the magic-link confirm button), and it'd burn /settings and /oauth/consent the same way. Both verify-page and settings-page have legit reasons to suppress Referer leakage (verify URL is a credential, settings shows the legacy connector URL).

**How to apply:** for any controller that needs *both* tight Referer hygiene *and* form CSRF, use `Referrer-Policy: same-origin` instead of `no-referrer`. Same-origin still strips Referer when navigating cross-origin (so the credential URL doesn't leak to claude.ai/google/etc.) but lets same-origin form POSTs carry a proper Origin. Set in three places consistently:
1. Response header in the controller (`response.set_header("Referrer-Policy", "same-origin")`)
2. `<meta name="referrer" content="same-origin">` in the view's `<head>`
3. (CSP `form-action` doesn't gate this but check it anyway since it lives in the same threat-model)

If you only fix one of those three layers, the meta tag (or response header) of the page that *contains the form* still wins and you keep getting `Origin: null`.

### claude.ai's MCP-OAuth integration is brittle and has known unresolved bugs

Confirmed via parallel research agents (Sonnet + Opus 4.7) on 2026-05-07: multiple open Anthropic issues track the same symptom — server-side OAuth completes per spec, claude.ai's frontend silently fails to call `/oauth/token`, no Bearer is ever sent. References (all open as of this writing): [claude-ai-mcp #46](https://github.com/anthropics/claude-ai-mcp/issues/46), [#163](https://github.com/anthropics/claude-ai-mcp/issues/163), [#215](https://github.com/anthropics/claude-ai-mcp/issues/215), [modelcontextprotocol #1674](https://github.com/modelcontextprotocol/modelcontextprotocol/issues/1674), [#2157](https://github.com/modelcontextprotocol/modelcontextprotocol/issues/2157).

**Why this matters here:** to land in Claude's MCP directory we need the integration to actually work. Our server-side is RFC-compliant (verified by curl roundtrip), so the only winnable game is matching every quirk that working impls (Cloudflare's `workers-oauth-provider`, Sentry, Linear) have stumbled onto.

**How to apply — these are now compat requirements, not tunables:**

| What | Where | Why |
|---|---|---|
| **302** (Found), not 303 | [oauth/authorizations_controller.rb#decide](app/controllers/oauth/authorizations_controller.rb) — explicit `status: :found` | Issue #215: working servers use 302, claude.ai parser treats 303 differently |
| **`token_type: "bearer"`** lowercase | [oauth/tokens_controller.rb#render_token_response](app/controllers/oauth/tokens_controller.rb) | RFC 6749 §5.1, matches Cloudflare ref-impl, strict clients seen rejecting capital B |
| **No `iss`** in auth-response redirect | [oauth/authorizations_controller.rb#decide](app/controllers/oauth/authorizations_controller.rb) | We tried RFC 9207, broke claude.ai (#2157 hints post-callback validation failure). Cloudflare doesn't include it either |
| **`grant_types: ["authorization_code", "refresh_token"]`** in DCR response | [oauth/clients_controller.rb#client_metadata](app/controllers/oauth/clients_controller.rb) | Strict clients infer "no refresh support" from missing entry → skip whole flow |
| **CORS** on `/oauth/token`, `/oauth/register`, `/.well-known/*`, `/mcp` + OPTIONS preflight routes | [concerns/oauth_cors.rb](app/controllers/concerns/oauth_cors.rb) + [routes.rb](config/routes.rb) | claude.ai's frontend uses fetch() — preflight failure = silent abort, server never sees the POST |
| **`form-action :self :https`** scoped to OAuth consent show/decide | [oauth/authorizations_controller.rb](app/controllers/oauth/authorizations_controller.rb) — `content_security_policy(only: [:show, :decide, :new, :start])` | See gotcha above |

If you "modernize" any of these (e.g. "spec-says-iss-is-good-let's-add-it", "lowercase-bearer-is-old-let's-Bearer-it"), retest in actual Claude Desktop. The spec is permissive; claude.ai's frontend is not.

## Commands

### `kamal deploy` — needs zsh wrapper

`KAMAL_REGISTRY_PASSWORD` lives in `~/.zshrc` (per [.kamal/secrets](.kamal/secrets) bash-eval lookup). Bash doesn't source zshrc, so plain `kamal deploy` from a Bash subprocess fails with `flag needs an argument: 'p' in -p` (docker-login gets an empty password).

**Always use:**

```bash
zsh -ic 'kamal deploy'
zsh -ic 'kamal app logs --lines 5000'
zsh -ic 'kamal app exec --primary "bin/rails runner ..."'
```

The `-ic` runs zsh interactively (`-i`) and executes the command (`-c`), which sources `~/.zshrc` first.

### Reset stuck signup rate-limit buckets (dev/test)

When a single test user blows through 3/IP/h or 5/domain/24h on `Signup.start` and you need to keep iterating:

```bash
zsh -ic 'kamal app exec --primary "bin/rails runner \"SolidCache::Entry.where(\\\"key LIKE ?\\\", \\\"%reg:%\\\").delete_all\""'
```

Clears all `reg:ip-h:*`, `reg:ip-d:*`, `reg:dom-d:*` buckets. The disposable-domain check is hardcoded in [signup.rb](app/services/signup.rb) `DISPOSABLE_DOMAINS`, can't reset that — use a different domain.

## Architecture quirks

### `/verify/:token` is dual-purpose (signup + OAuth-consent step)

The same magic-link URL handles two paths in [verifications_controller.rb#confirm](app/controllers/verifications_controller.rb):
- If `EmailVerification#oauth_flow?` (i.e. associated with an `OauthAuthorizationRequest`), POST mints a signed grant and redirects to `/oauth/consent/:request_token?grant=…`.
- Otherwise (plain signup from the landing form), POST establishes a 30-min Settings session and renders `verifications/verified.html.erb`.

Look for the `oauth_flow?` branch when debugging post-verify behavior.

### McpController accepts THREE auth methods

In [mcp_controller.rb#authenticate_from_request](app/controllers/mcp_controller.rb):
1. **OAuth Bearer** (`Authorization: Bearer mcpa_oauth_…`) — the modern path, scope-enforced, audience-bound (RFC 8707), revocable per-client via /settings.
2. **Legacy Bearer** (`Authorization: Bearer mcpa_…`) — the user's master `api_token`, treated as having all scopes.
3. **Legacy `?token=` query param** — same master `api_token` as #2 but in the URL. Accepted for back-compat (claude-code CLI still uses it). **Not surfaced in any new UX**; only available via [/settings legacy disclosure](app/views/settings/show.html.erb).

The query-param path leaks into kamal-proxy access logs (Rails `filter_parameters` only filters Rails app logs). Plan to phase out once usage is zero — see followups below.

## Followups (acknowledged but not yet fixed)

- **Proxy log token leak** (Sonnet review M1): kamal-proxy access logs the full URL including `?token=mcpa_xxx`. Rails app logs filter it; the Go proxy doesn't. Mitigation path: deprecate `?token=` URLs entirely once nothing legitimate uses them. Today: single-user prod, contained risk.
- **MCP throttle key change pending** (Sonnet review M2): if [throttle_if_authenticated](app/controllers/mcp_controller.rb) is still bucketing by raw token string when you read this, an attacker who knows a victim's token can DoS the victim's bucket from any IP. Move to per-`user_id` keying after auth resolves.

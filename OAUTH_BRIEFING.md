# OAuth 2.1 + PKCE for mcp-analytics — Implementation Brief

> Brief for a cloud-resident coding agent to build OAuth 2.1 with PKCE for the mcp-analytics MCP server. The product is live, scoped to a single user today (`info@spreenovate.de`), so we have full freedom to deprecate the legacy URL-token flow once OAuth ships.

---

## 1. Context

**mcp-analytics** is a Rails 8 + Go ingest + ClickHouse SaaS that exposes web analytics via the Model Context Protocol (MCP). Today, authentication works by appending a bearer token to the MCP URL:

```
https://mcp-analytics.com/mcp?token=mcpa_YL6m0Cjp...
```

The user pastes this URL into Claude / Cursor / ChatGPT as a custom MCP connector. It works but:

- Anthropic's Connector Directory **requires** OAuth 2.1 with Dynamic Client Registration.
- ChatGPT Connectors **require** the same.
- The "paste a token-bearing URL" UX is friction-heavy versus a click-to-authorize flow.
- Some MCP clients do not let the user paste arbitrary URLs and expect the OAuth dance.

This brief specifies a complete OAuth 2.1 + PKCE implementation per the **MCP Authorization spec (2025-06-18 protocol revision)** that sits alongside the existing token flow without breaking it.

---

## 2. Goals

1. Conform to the MCP Authorization spec so we can submit to:
   - Anthropic Connector Directory
   - ChatGPT Connectors
   - any MCP client that expects OAuth (Smithery, OpenClaw, OpenCode, …)
2. Provide a smooth, brand-consistent UX:
   - User pastes only `https://mcp-analytics.com/mcp` (no token)
   - Client follows discovery → registers → redirects user to consent
   - User confirms identity via email magic-link, then approves
   - Client gets access + refresh tokens, calls MCP normally
3. Keep the legacy `?token=` flow working for CLI / scripted use cases that benefit from it.
4. Be implementable in **1–2 working days** by a single agent.

---

## 3. Non-goals (explicit out-of-scope)

- 2FA / TOTP — leave a clean hook for it but do not implement.
- Per-account password login — the magic-link flow is the only login path.
- Multiple redirect URIs per client — accept one, document that DCR can be repeated for additional ones.
- Granular per-tool scopes — ship a **single scope `analytics`** but design the schema and code so the resource server can later accept `analytics:read`, `analytics:write`, `sites:write` etc. without migrations.
- OAuth flows other than Authorization Code with PKCE (no Implicit, no Password Grant, no Client Credentials).
- Custom UI for managing connected clients beyond a basic list-and-revoke page (P1 polish, can ship in a follow-up).

---

## 4. Decisions (with rationale)

| # | Decision | Rationale |
|---|---|---|
| 1 | Magic-link to email is the only login path during OAuth flow | Consistent with existing signup. No password infra. Future 2FA can layer on top of the post-magic-link state. |
| 2 | Legacy `?token=mcpa_xxx` URL flow stays working indefinitely | Zero existing users would be migrated, but the token flow is a legitimate CLI/scripted use case. Document on landing as "for headless / CI use". |
| 3 | Single scope `analytics` granted today | Granular scopes (`analytics:read`, `:write`) deferred until users actually request them. Schema stores scope as a string column accepting any space-delimited list. |
| 4 | Opaque random tokens + DB lookup. Refresh tokens supported. | Simple revocation, no JWT key-rotation pain. Access tokens 1h TTL, refresh tokens 30d sliding. |
| 5 | Custom implementation, no Doorkeeper | Doorkeeper's defaults conflict with our brutalist UI and bring views/migrations we don't want. The OAuth 2.1 + PKCE + DCR surface is small enough (~500 LOC) to own. |
| 6 | Consent screen uses the same brutalist style as `/docs` | Brand consistency. Reuse `_brutalist_doc_styles.html.erb`. |

---

## 5. MCP-Spec compliance checklist

The MCP Authorization spec (revision 2025-06-18) requires the following. Implement all of them.

- [ ] **PKCE mandatory** for all authorization code flows. Reject `authorize` requests missing `code_challenge` or `code_challenge_method`. Only accept `S256` (reject `plain`).
- [ ] **`/.well-known/oauth-authorization-server`** discovery endpoint. RFC 8414 metadata document.
- [ ] **`/.well-known/oauth-protected-resource`** at the resource server (the MCP endpoint). RFC 9728 metadata document.
- [ ] **Dynamic Client Registration** (RFC 7591) at `/oauth/register`. Open registration, no admin approval. Rate-limited.
- [ ] **`WWW-Authenticate`** header on 401 from the MCP endpoint, pointing to the authorization server discovery URL. Format per RFC 9728 §5.1.
- [ ] **Resource Indicators** (RFC 8707): the access token must be bound to the MCP endpoint URL via the `resource` parameter. Validate at token introspection time.
- [ ] **HTTPS everywhere** for all OAuth endpoints. Reject non-TLS in production.
- [ ] **Authorization Code single-use**: code expires after 60 seconds, can only be exchanged once.
- [ ] **State parameter** opaque to server, echoed back unchanged to the redirect URI.

---

## 6. Database schema

Five new tables. All in SQLite (Rails primary DB). Migrations should be additive — do not touch existing tables.

```ruby
# db/migrate/[ts]_create_oauth_clients.rb
create_table :oauth_clients do |t|
  t.string  :client_id,         null: false, index: { unique: true } # opaque, ~32 chars
  t.string  :client_secret_digest # nullable: public clients (PKCE-only) get no secret
  t.string  :client_name,       null: false
  t.string  :redirect_uris,     null: false # JSON array, multiple allowed per client per spec
  t.string  :grant_types,       null: false, default: "authorization_code,refresh_token"
  t.string  :token_endpoint_auth_method, null: false, default: "none" # 'none' for PKCE public clients
  t.string  :scope,             null: false, default: "analytics"
  t.string  :client_uri               # informational, displayed on consent screen
  t.string  :logo_uri                 # informational
  t.string  :tos_uri
  t.string  :policy_uri
  t.text    :metadata                 # JSON blob for any extra DCR fields we don't model
  t.datetime :created_at, null: false
end

# db/migrate/[ts]_create_oauth_authorizations.rb
# An "authorization" = a user's standing grant to a client. One row per (user, client) once consented.
create_table :oauth_authorizations do |t|
  t.references :user,         null: false, foreign_key: true
  t.references :oauth_client, null: false, foreign_key: true
  t.string  :scope,           null: false # space-delimited, what was actually granted
  t.datetime :revoked_at      # soft-revoke
  t.timestamps
  t.index [:user_id, :oauth_client_id], unique: true
end

# db/migrate/[ts]_create_oauth_authorization_codes.rb
# Short-lived codes exchanged for tokens.
create_table :oauth_authorization_codes do |t|
  t.references :oauth_authorization, null: false, foreign_key: true
  t.string  :code_digest,     null: false, index: { unique: true } # SHA-256 of the random code
  t.string  :code_challenge,  null: false # PKCE
  t.string  :code_challenge_method, null: false, default: "S256"
  t.string  :redirect_uri,    null: false # must match exactly at token exchange
  t.string  :resource         # RFC 8707 resource indicator, may be null
  t.string  :scope,           null: false
  t.datetime :expires_at,     null: false # 60 seconds from creation
  t.datetime :used_at         # single-use; set on first exchange
  t.timestamps
end

# db/migrate/[ts]_create_oauth_access_tokens.rb
create_table :oauth_access_tokens do |t|
  t.references :oauth_authorization, null: false, foreign_key: true
  t.string  :token_digest,    null: false, index: { unique: true } # SHA-256
  t.string  :scope,           null: false
  t.string  :resource         # RFC 8707 binding
  t.datetime :expires_at,     null: false # default: 1h
  t.datetime :revoked_at
  t.timestamps
end

# db/migrate/[ts]_create_oauth_refresh_tokens.rb
create_table :oauth_refresh_tokens do |t|
  t.references :oauth_authorization, null: false, foreign_key: true
  t.string  :token_digest,    null: false, index: { unique: true }
  t.string  :scope,           null: false
  t.datetime :expires_at,     null: false # 30d sliding
  t.datetime :revoked_at
  t.references :replaced_by_id, foreign_key: { to_table: :oauth_refresh_tokens }
  t.timestamps
end
```

**Why digest columns:** never store the raw token in the DB. On every request, hash the presented token and look up by digest. Constant-time comparison via `ActiveSupport::SecurityUtils.secure_compare` if needed.

**Why authorization-code → authorization → user / client:** consent is per-(user, client) and lasts until revoked. Tokens reference the standing authorization, so revoking the authorization cascades.

---

## 7. Endpoints

All endpoints live under `/oauth/*` plus the two `.well-known/` paths. Routes go in `config/routes.rb`.

### 7.1 Discovery

#### `GET /.well-known/oauth-authorization-server`

Returns RFC 8414 metadata. Static JSON, served by a controller method.

```json
{
  "issuer": "https://mcp-analytics.com",
  "authorization_endpoint": "https://mcp-analytics.com/oauth/authorize",
  "token_endpoint": "https://mcp-analytics.com/oauth/token",
  "registration_endpoint": "https://mcp-analytics.com/oauth/register",
  "revocation_endpoint": "https://mcp-analytics.com/oauth/revoke",
  "scopes_supported": ["analytics"],
  "response_types_supported": ["code"],
  "grant_types_supported": ["authorization_code", "refresh_token"],
  "code_challenge_methods_supported": ["S256"],
  "token_endpoint_auth_methods_supported": ["none"]
}
```

#### `GET /.well-known/oauth-protected-resource`

RFC 9728 metadata for the MCP endpoint.

```json
{
  "resource": "https://mcp-analytics.com/mcp",
  "authorization_servers": ["https://mcp-analytics.com"],
  "bearer_methods_supported": ["header"],
  "scopes_supported": ["analytics"]
}
```

### 7.2 Dynamic Client Registration

#### `POST /oauth/register`

RFC 7591. Accepts JSON body:

```json
{
  "client_name": "Claude.ai",
  "redirect_uris": ["https://claude.ai/callback"],
  "grant_types": ["authorization_code", "refresh_token"],
  "token_endpoint_auth_method": "none",
  "scope": "analytics"
}
```

Returns 201 with the registered client metadata + `client_id`. No `client_secret` for public clients (`token_endpoint_auth_method: none`).

**Rate limit:** 10 per IP per hour. Reject duplicates (same `client_name` + identical `redirect_uris[0]`) by returning the existing record, idempotent.

### 7.3 Authorization

#### `GET /oauth/authorize`

Query params:
- `response_type=code` (required)
- `client_id` (required)
- `redirect_uri` (required, must be in client's registered list)
- `scope` (optional, defaults to `analytics`)
- `state` (recommended, opaque)
- `code_challenge` (required)
- `code_challenge_method=S256` (required)
- `resource` (optional, RFC 8707 — bind token to specific resource)

Flow:
1. Validate all params. Render an error page (not a redirect) if `client_id` or `redirect_uri` invalid — never redirect to an attacker-controlled URI before validating it.
2. If user is not authenticated in this browser session: render the **email-magic-link login form**. After link is clicked, redirect back to `/oauth/authorize` with the same params (preserve the original query in the magic-link state).
3. If user has a non-revoked `oauth_authorization` for this client + scope, **skip the consent screen** and issue the code immediately.
4. Otherwise, render the **consent screen** showing client name + scope + "Allow / Deny" buttons.
5. On Allow: create `oauth_authorization`, generate authorization code, persist with PKCE challenge + redirect_uri + resource + scope, redirect to `redirect_uri?code=...&state=...`.
6. On Deny: redirect to `redirect_uri?error=access_denied&state=...`.

### 7.4 Token

#### `POST /oauth/token`

Two grant types:

**a) `authorization_code`**

Body (`application/x-www-form-urlencoded`):
- `grant_type=authorization_code`
- `code=...`
- `redirect_uri=...` (must match exactly what was stored)
- `client_id=...`
- `code_verifier=...` (PKCE; SHA-256 of which must equal stored `code_challenge`)

Response (200):
```json
{
  "access_token": "mcpa_at_...",
  "token_type": "Bearer",
  "expires_in": 3600,
  "refresh_token": "mcpa_rt_...",
  "scope": "analytics"
}
```

Mark the auth code as `used_at` immediately. Reject if already used (replay attempt).

**b) `refresh_token`**

Body:
- `grant_type=refresh_token`
- `refresh_token=...`
- `client_id=...`

**Refresh token rotation:** issue a new refresh token, mark the old one as `revoked_at + replaced_by_id`. If a revoked refresh token is presented, **revoke the entire authorization** (token theft signal) — RFC 6749 §10.4 best practice.

### 7.5 Revocation

#### `POST /oauth/revoke`

RFC 7009. Body: `token=...&token_type_hint=access_token|refresh_token`. Idempotent.

### 7.6 MCP endpoint integration

`POST /mcp` and `GET /mcp` accept Bearer tokens **in addition to** the legacy `?token=` URL param.

```ruby
# In McpController#authenticate_user!
def authenticate_user!
  if (header = request.authorization) && header.start_with?("Bearer ")
    raw = header.sub(/\ABearer /, "")
    token = OauthAccessToken.find_by(token_digest: Digest::SHA256.hexdigest(raw))
    if token && token.usable? && token.bound_to?(request.url)
      @current_user = token.oauth_authorization.user
      return true
    end
  end

  if (raw = params[:token]).present?
    user = User.find_by(api_token: raw)
    return @current_user = user if user
  end

  render_unauthorized
end

def render_unauthorized
  response.set_header(
    "WWW-Authenticate",
    %(Bearer resource_metadata="https://mcp-analytics.com/.well-known/oauth-protected-resource")
  )
  render json: { error: "invalid_token" }, status: :unauthorized
end
```

---

## 8. UX flow (end-to-end)

```
[User in Claude]
   "Add mcp-analytics as a connector."
   [Claude prompts user to enter the MCP URL]
[User pastes]
   https://mcp-analytics.com/mcp
[Claude]
   1. POST /mcp without token → 401 + WWW-Authenticate
   2. GET /.well-known/oauth-protected-resource
   3. GET /.well-known/oauth-authorization-server
   4. POST /oauth/register {client_name: "Claude.ai", redirect_uris: [...]}
      → {client_id: "..."}
   5. Open browser at /oauth/authorize?... with PKCE challenge
[User in browser]
   - Sees: "Sign in to authorize Claude.ai"
   - Enters email
   - Receives magic-link email
   - Clicks link → /oauth/magic_link?token=xyz
   - Browser lands at consent screen:
     "Claude.ai wants access to your mcp-analytics data."
     [Allow] [Deny]
   - Clicks Allow
   - Redirected to https://claude.ai/callback?code=...&state=...
[Claude]
   6. POST /oauth/token {grant_type, code, code_verifier, ...}
      → {access_token, refresh_token, expires_in: 3600}
   7. POST /mcp with `Authorization: Bearer <access_token>`
      → tool list, normal MCP traffic begins
[1h later]
[Claude]
   8. POST /oauth/token {grant_type: refresh_token, refresh_token: ...}
      → new pair, old refresh marked replaced
```

---

## 9. File-by-file implementation map

```
config/routes.rb                                     # add oauth routes + .well-known
app/controllers/oauth/discovery_controller.rb        # 2 .well-known endpoints
app/controllers/oauth/registration_controller.rb     # POST /oauth/register
app/controllers/oauth/authorize_controller.rb        # GET /oauth/authorize, POST /oauth/authorize/decide
app/controllers/oauth/token_controller.rb            # POST /oauth/token, POST /oauth/revoke
app/controllers/oauth/login_controller.rb            # magic-link inside the OAuth flow
app/controllers/concerns/oauth_authentication.rb     # shared session helpers
app/controllers/mcp_controller.rb                    # add Bearer-token support + WWW-Authenticate

app/models/oauth_client.rb
app/models/oauth_authorization.rb
app/models/oauth_authorization_code.rb
app/models/oauth_access_token.rb
app/models/oauth_refresh_token.rb

app/services/oauth/issue_authorization_code.rb       # creates code with PKCE binding
app/services/oauth/exchange_authorization_code.rb    # validates PKCE, issues access+refresh
app/services/oauth/refresh_tokens.rb                 # rotation + theft detection
app/services/oauth/verify_pkce.rb                    # S256 challenge ↔ verifier
app/services/oauth/random_token.rb                   # secure random + prefix helper

app/views/oauth/login.html.erb                       # email entry form
app/views/oauth/login_check.html.erb                 # "check inbox" page
app/views/oauth/consent.html.erb                     # Allow / Deny screen
app/views/oauth/error.html.erb                       # for invalid client/redirect cases

app/mailers/oauth_login_mailer.rb                    # sends magic link

db/migrate/*                                         # 5 migrations as above

test/models/oauth_*_test.rb
test/controllers/oauth/*_test.rb
test/services/oauth/*_test.rb
test/integration/oauth_flow_test.rb                  # end-to-end happy path + failure modes
```

---

## 10. Test plan

The implementing agent must ship the following test coverage. Use Minitest (project convention).

### Model tests
- Token digest uniqueness, never persists raw token.
- Authorization code single-use enforcement.
- Refresh token replacement chain.
- Authorization revocation cascades to all tokens.
- Expired tokens / codes return `usable? == false`.

### Controller tests (per endpoint)
- Discovery endpoints return spec-compliant JSON, correct content-type.
- DCR rejects malformed bodies, rate-limits per IP.
- Authorize rejects unknown client, unknown redirect_uri, missing PKCE, plain (non-S256) PKCE.
- Authorize redirects to login when unauthenticated, preserves the original params through the magic-link round-trip.
- Authorize skips consent if the user already has a non-revoked authorization.
- Token endpoint rejects: replayed code, wrong code_verifier, wrong redirect_uri, expired code.
- Refresh token rotation issues new pair, marks old as replaced.
- Replay of revoked refresh token revokes the entire authorization.
- Revocation endpoint is idempotent.

### Integration test
- End-to-end flow from POST /mcp without token → discovery → DCR → authorize → magic-link → consent → code → token → POST /mcp with bearer.
- WWW-Authenticate header on 401 contains the `resource_metadata=` directive.

### Backwards compat
- Existing `?token=mcpa_xxx` flow still authenticates a user.
- A user can have both an active OAuth authorization and the legacy api_token; both work in parallel.

Target: 30+ new tests. Existing 101 must stay green. CI runs `bin/rails test` and `cd ingestion && go test ./...`.

---

## 11. Backwards compatibility

- The `User#api_token` column **stays**, no migration removes it.
- `McpController` checks Bearer first, falls back to `?token=` param.
- Landing page copy keeps both options. Suggested wording (apply to `app/views/pages/home.html.erb` and `/docs`):
  > **For Claude / Cursor / ChatGPT users:** paste `https://mcp-analytics.com/mcp` and authorize once.
  > **For CLI / scripted use:** copy the URL with your token from the verify page.

---

## 12. Security checklist (mandatory; subagent #2 will audit)

- [ ] Tokens stored as SHA-256 digests only. Raw tokens never logged, never returned in error messages.
- [ ] Authorization code single-use. Replay marks the entire authorization compromised → revoke all.
- [ ] Refresh token rotation + theft detection (revoked → revoke authorization).
- [ ] PKCE `S256` only; `plain` rejected.
- [ ] Reject `none` PKCE method.
- [ ] `redirect_uri` matched exactly (no substring, no prefix). Localhost loopback exception per RFC 8252 §7.3 — accept any port for `http://127.0.0.1` and `http://localhost`.
- [ ] Authorization codes expire in 60 seconds.
- [ ] Access tokens expire in 1 hour.
- [ ] Refresh tokens expire in 30 days, sliding (each rotation extends).
- [ ] Resource indicator (RFC 8707) bound at token issue, validated at MCP endpoint.
- [ ] All OAuth endpoints rate-limited (RateLimit service exists, reuse it):
  - `/oauth/register`: 10/IP/h
  - `/oauth/token`: 60/IP/m
  - `/oauth/authorize`: 30/IP/m
  - magic-link send: 3/IP/h, 5/email/d (reuse Signup limits)
- [ ] HTTPS required. In production, reject non-HTTPS to OAuth endpoints (Rails `config.force_ssl = true` already on, verify).
- [ ] `state` parameter echoed back unchanged.
- [ ] CSRF token NOT required on `/oauth/token` (token endpoint is API), but IS required on the consent POST.
- [ ] Constant-time comparison for any equality check on secrets (`ActiveSupport::SecurityUtils.secure_compare`).
- [ ] Magic-link tokens single-use, 15 min TTL.
- [ ] No `client_secret` issued for public clients (`token_endpoint_auth_method: none`); reject any `client_secret` presented at token endpoint by such clients.
- [ ] Logging: log `client_id`, never log tokens, codes, or magic-link strings.
- [ ] Error responses follow OAuth 2.0 error format (`{"error": "invalid_grant", "error_description": "..."}`) — keep `error_description` generic to not leak internals.
- [ ] Open redirect protection: only redirect to URIs registered for the client.

---

## 13. 2FA hook (deliberately deferred but design space)

Future 2FA via WebAuthn / TOTP / phone-based flow will plug in **after the magic-link click**, before the consent screen renders. Design the post-login state to support an extra step:

```ruby
session[:oauth_user_id] = user.id
session[:oauth_login_at] = Time.current.to_i
# Future: session[:oauth_needs_2fa] = user.totp_enabled?
# If set, redirect to /oauth/2fa instead of consent.
```

Do not add 2FA columns to the User model now. Just leave the controller flow in a shape that admits an extra step.

---

## 14. Deploy checklist

After merging the feature branch:

1. `bin/rails db:migrate` runs automatically on Kamal deploy via `bin/setup`-equivalent. Verify migrations are idempotent.
2. `kamal deploy`.
3. Smoke-test with `curl`:
   ```bash
   curl -s https://mcp-analytics.com/.well-known/oauth-authorization-server | jq .
   curl -s https://mcp-analytics.com/.well-known/oauth-protected-resource | jq .
   curl -X POST https://mcp-analytics.com/oauth/register \
     -H "Content-Type: application/json" \
     -d '{"client_name":"smoke","redirect_uris":["https://example.com/cb"]}' | jq .
   curl -i https://mcp-analytics.com/mcp # expect 401 + WWW-Authenticate
   ```
4. Test full flow in the Claude desktop app: paste `https://mcp-analytics.com/mcp` (no token), expect browser to open, magic-link to land, consent screen, redirect.
5. After successful flow, the existing `?token=mcpa_xxx` URL should still work — verify in a separate Claude project.

---

## 15. Dual-subagent review (mandatory before merge)

After implementation, the implementing agent must:

### Subagent A — General code review
Spawn an agent with this prompt:

> Review the OAuth Phase 2 implementation in this branch end-to-end. Check: idiomatic Rails 8 conventions, readability, test coverage versus the test plan in OAUTH_BRIEFING.md §10, naming consistency with the existing codebase (look at `app/services/signup.rb` and `app/services/mcp/` for conventions), correct use of `ActiveSupport::SecurityUtils.secure_compare`, proper transaction boundaries on multi-row writes (issuing tokens, refresh-token rotation), and that the legacy `?token=` flow in `McpController` still works. Report a punch list of must-fix vs nice-to-have issues, under 600 words.

### Subagent B — Security audit
Spawn an agent with this prompt:

> Security audit of the OAuth Phase 2 implementation in this branch. Verify every item in OAUTH_BRIEFING.md §12 (security checklist) is actually enforced by the code, not just intended. Specifically check: PKCE S256 enforcement (no `plain` accepted), authorization code single-use (replay test), refresh token rotation with theft detection (replay revokes the authorization), redirect_uri exact match (no open redirect), resource indicator binding, rate limits on every OAuth endpoint, no raw tokens in DB / logs / error responses, constant-time comparison for token lookup. Also test for: timing attacks on token lookup, CSRF on the consent POST, session fixation across the magic-link round-trip. Report concrete findings with file:line references and severity (critical / high / medium / low). Under 600 words.

Both subagents must run before opening the PR for human review. Address all critical + high findings; medium / low can ship as follow-up issues.

---

## 16. Estimated effort

- DB migrations + models: **1.5h**
- Discovery + DCR endpoints: **1h**
- Authorize + login (magic-link) controllers: **3h**
- Token + refresh + revoke endpoints: **2h**
- MCP controller integration + WWW-Authenticate: **1h**
- Consent screen view (brutalist): **1h**
- Tests (~30 of them): **3h**
- Subagent reviews + fixes: **2h**

**Total: ~14h, realistically 1.5 working days.**

---

## 17. Out-of-scope follow-ups (track as separate issues, do not implement now)

- A user-facing "Connected apps" page where the user can list their `oauth_authorizations` and click Revoke.
- Granular scopes (`analytics:read`, `analytics:write`, `sites:write`).
- 2FA support.
- Admin tooling for inspecting OAuth client registrations.
- OpenID Connect (we do not need identity claims, just access).

---

## Appendix A — Conventions used in this codebase

- Rails 8 with Solid Queue + Solid Cache. SQLite primary DB.
- ClickHouse for analytics events (NOT for OAuth state — OAuth lives in SQLite).
- All view styles inline in `<style>` blocks per page. Shared brutalist styles in `app/views/pages/_brutalist_doc_styles.html.erb`. Reuse this partial for the consent + login views.
- Self-hosted fonts via `app/views/layouts/_fonts.html.erb`. Render this in any new view that needs the brand fonts.
- Rate-limiting service: `RateLimit.allow?(key:, limit:, window:)`. See `app/services/signup.rb` for usage.
- Email sending: `ApplicationMailer` subclasses, `deliver_later` via Solid Queue. See `app/mailers/verification_mailer.rb` for the existing pattern.
- Test framework: Minitest (no RSpec). Run via `bin/rails test`.
- Em-dashes are forbidden in user-facing copy. Use `, ` or `. ` or `(...)` instead.

## Appendix B — What the user sees on the consent screen

Brutalist style, single page:

```
[> mcp-analytics]

YOU ARE GRANTING ACCESS

  Claude.ai wants to access your mcp-analytics data.

  - Read all your sites and their analytics
  - Add and remove sites
  - Modify account settings
  - Generate new API tokens

  Signed in as: info@spreenovate.de

  [ DENY ]      [ ALLOW ]

  By approving, you grant Claude.ai indefinite access until you revoke
  it. You can revoke any time from your account page.
```

Match the visual treatment of the `/docs` agent-notice callout (black background, neon green accent shadow, JetBrains Mono labels, Space Grotesk H2).

---

End of brief. Implementing agent: read this file, then start with `db/migrate/` and work outward.

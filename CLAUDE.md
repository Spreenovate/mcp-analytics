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

### Alpine ships busybox, not GNU — smoke-test the real script, not a paraphrase

The ingest container is `alpine:3.20` so its `/bin/sed`, `/usr/bin/timeout`, `/bin/sh` are all busybox 1.36, not GNU. Two flag-level differences that have bitten us:

- **`sed -u` is GNU-only.** Busybox sed exits with `unrecognized option: u` before reading any input. Was deployed to prod in [entrypoint.sh](ingestion/entrypoint.sh) and ate the entire reclassify run via the broken pipe. Busybox sed is line-buffered by default anyway, so just drop `-u`.
- **`timeout` without `-k` doesn't escalate.** Busybox `timeout SECS PROG` sends SIGTERM only — if the process ignores it, the timeout is a no-op. Use `timeout -k 30 300 PROG` for "SIGTERM at 5 min, SIGKILL 30 s later".

**Methodology note:** my pre-deploy smoke-test ran `sed s/.../` (no flags) and reported "all good", because I'd written a stripped-down version of the entrypoint logic in the test instead of running the actual `entrypoint.sh`. The real script with `sed -u` was never exercised. Lesson: when smoke-testing a shell script in the actual container image, **invoke the script verbatim** (e.g. mount over `/app/entrypoint.sh` with a stub for the binary it execs), don't rewrite a "simplified version" of the same logic. Strip-down loses exactly the kind of flag-level detail that breaks at runtime.

### `outputSchema` — declare permissive first, never strict-without-tests

MCP spec 2025-06-18 §`outputSchema`: *"If specified, server's response to a tools/call for this tool MUST conform to this schema."* Claude.ai has been historically strict about adjacent details (302 vs 303, no `iss`, lowercase `bearer`, `sed -u` quirks under busybox) — it's plausible that Claude or the next strict client will hard-reject responses on `outputSchema` mismatch too. We haven't proven it does, but the asymmetry is wrong: a tight schema costs us a future-debugging headache, a loose schema costs us nothing.

**Convention:** all 23 tool entries in [tool_schemas.rb](app/services/mcp/tool_schemas.rb) reference a single `PERMISSIVE_OUTPUT = { type: "object" }` constant. Spec-formal-conformant (every tool returns an object — `Mcp::Server#tool_success` wraps arrays under `items`) without constraining shape. OpenAI's Apps SDK submission is happy with this.

**When to tighten:** only with concrete reason (e.g. an MCP client that demonstrably benefits from richer schema introspection) AND with tests that validate the real tool's return value against the declared schema. Don't hand-write a richer outputSchema and hope it matches — the response can drift any time a tool implementation changes a key name and the schema would need to be updated in lockstep.

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

### Content marketing surface (`/blog`, `/vs`, `/mcp/tools`, `/ai-crawler-index`)

Markdown-backed content lives in `app/views/blog/posts/{en,de}/*.md` and
`app/views/comparisons/{en,de}/*.md`. PORO models [blog_post.rb](app/models/blog_post.rb)
and [comparison.rb](app/models/comparison.rb) parse YAML frontmatter + body,
render via [kramdown](https://kramdown.gettalong.org) with the GFM parser. No
ActiveRecord, no DB rows. The MCP tool catalog at `/mcp/tools/:slug` is generated
on the fly by [mcp_tool_page.rb](app/models/mcp_tool_page.rb) from
`Mcp::ToolSchemas::AUTHENTICATED`, so the page can't drift from what the actual
server exposes.

**Invariants worth knowing before touching this code:**

- **Slug regex is `\A[a-z0-9][a-z0-9\-]*\z`** at every layer that accepts user-controllable
  slug input (`BlogPost::SLUG_RE`, `Comparison.find`, route constraints in [routes.rb](config/routes.rb)).
  Underscores are NOT allowed at the URL layer. The MCP tool layer maps URL dashes to schema
  underscores (`tr("-", "_")`) so the URL `/mcp/tools/top-pages` resolves to the schema entry
  `top_pages`. Don't loosen the regex without adding a redirect from underscore form to dash form.
- **`body_html` is cached in `Rails.cache` keyed by file mtime.** Edit a `.md`, the next
  request renders fresh; no manual cache bust. Caveat: docker/kamal builds reset mtime to
  build time, so production cache keys = deploy timestamp.
- **JSON-LD must go through `ApplicationHelper#json_ld`**, not `.to_json.html_safe` directly.
  The helper adds a defensive `</` escape so frontmatter values containing `</script>` can't
  break out of the script context.
- **robots.txt named-bot stanzas REPLACE the wildcard block** per RFC 9309. Every named-UA
  block in [public/robots.txt](public/robots.txt) repeats the full Disallow set. Don't add a new
  bot block without copying the Disallow lines, or that bot is free to crawl `/oauth/*`.
- **DE/EN hreflang must be reciprocal.** If a DE post declares `hreflang_alt: foo`, the EN post
  at `foo.md` must declare `hreflang_alt: <de-counterpart-slug>` too. Google ignores one-way hreflang.

If something breaks, smoke-test with the integration session pattern in
[/tmp/v3b_smoke.rb](#) (history) — `ActionDispatch::Integration::Session.new(Rails.application)`
under `RAILS_ENV=test` bypasses the host filter and lets you GET every content URL in one script.

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

These are real issues, parked because we're single-user-prod for now and the cost/benefit doesn't justify a stop-everything fix. Reactivate when we have real users.

- **Proxy log token leak.** kamal-proxy access logs the full URL including `?token=mcpa_xxx`. Rails app logs filter it; the Go proxy doesn't. Mitigation in flight: every `?token=`-authed response now carries `Deprecation: true` + `Sunset` (~6 months) + a `legacy_token_query_used` audit event (rate-limited to 1/h/user) — see [mcp_controller.rb#flag_token_query_deprecation](app/controllers/mcp_controller.rb). Plan: when the audit log shows zero use for ~30 days, delete the query-param branch from `authenticate_from_request` entirely.

- **`regenerate_api_token` MCP tool still hands out a `?token=`-shaped URL.** Same response carries the deprecation header (because the rotation itself was likely called via the deprecated path), so we're handing the user a fresh URL labelled deprecated. Inconsistent — once the query path is gone, the tool's response should change to the bare base URL plus a "use Authorization: Bearer …" hint.

- **TOCTOU in `RateLimit` / `McpRateBucket` bucket-init.** [mcp_rate_bucket.rb](app/services/mcp_rate_bucket.rb) and [rate_limit.rb](app/services/rate_limit.rb) both do `increment` → on `nil` (key not yet present) → `write(1)`. Concurrent first-request-of-window POSTs can both see `nil` and both `write(1)`, resetting the counter. With HTTP/2 multiplexing trivially exploitable for ~2× headroom at the window edge. Per-user 60/min is still soft so it's bounded grief, but worth atomicising (write_unless_exists then increment, or move to Redis/Lua).

- **`OauthAccessToken#touch_used!` runs pre-rate-limit.** [mcp_controller.rb#authenticate_from_request](app/controllers/mcp_controller.rb) calls `touch_used!` before `rate_limit_exceeded?`. Already throttled internally (60s) so a rate-limited attacker can't keep updating it, but a stolen-token attacker can keep the connector's `last_used_at` looking fresh in /settings, masking the theft. Move the touch to after the rate-limit gate when you next pass through.

- **OAuth + legacy share one user-bucket.** Bucket key is `"user:#{user.id}"`, so a misbehaving OAuth client can exhaust the budget that legacy `?token=` traffic also relies on (and vice versa). Intentional today (no cross-user DoS via a stolen-but-still-valid token) but worth a per-credential sub-bucket if a single account starts running multiple loud clients.

### Reclassify auto-loop in the ingest container

The ingest container ([entrypoint.sh](ingestion/entrypoint.sh)) runs `/app/reclassify --apply` once on boot and every 24 h thereafter via a background shell loop. Idempotent (sub-second when no changes) and lifecycle-bound to ingest. Two parallel reviews (Opus + Sonnet, 2026-05-08) flagged the following real-but-deferred issues:

- **Reclassify loads all distinct UAs into memory unbounded.** [reclassify/main.go#queryDistinctUAs](ingestion/cmd/reclassify/main.go) does a single `SELECT user_agent, traffic_class FROM events GROUP BY …`. With millions of distinct UAs (random-spam scenario) the slice grows to GB-scale, OOMs the container; the `|| true` in entrypoint.sh swallows the failure silently. Fix: paginate or stream the result, or `LIMIT` with a deterministic order. Not urgent at current data volume.
- **ClickHouse mutation queue can stack.** Each (UA, old_class) pair becomes an `ALTER TABLE events UPDATE` mutation, async by default. The 24 h loop re-queues the same ones if prior mutations haven't completed. Fix: `mutations_sync=2` on the HTTP call, OR pre-run check `SELECT count() FROM system.mutations WHERE NOT is_done` and skip if non-zero.
- **Rolling-restart concurrency.** `kamal accessory reboot ingest` overlaps old + new container for a few seconds — both run reclassify in parallel. Mutations are idempotent but doubled queue load. Fix: a CH advisory lock (e.g. `INSERT INTO reclassify_lock VALUES (now())` with a TTL) skipped on the second runner.
- **Shared CH credentials.** Reclassify uses the same `CLICKHOUSE_USER` as ingest — has both INSERT and ALTER UPDATE. A scoped `reclassify_user` with only `ALTER ... UPDATE` would tighten blast radius post-RCE on the ingest server.
- **Goroutine-instead-of-shell-loop.** A scheduler goroutine inside `cmd/ingest` would integrate ctx-cancel on shutdown, structured slog, optional Prometheus metrics, and avoid the busybox-timeout / pipefail dance entirely. Refactor when there's reason to touch this code anyway. Trade-off: a panic in reclassify code could take down ingest unless wrapped — keep the recover() if you migrate.

The on-boot 30 s sleep means a slow ClickHouse start can miss the boot-heal silently and wait 24 h for the next attempt. Acceptable at MVP scale; document if SLA tightens.

A second ops note: `mutations_sync=1` (added to fix the queue-stacking issue) makes each UPDATE block until CH finishes the mutation. Combined with the outer `timeout 300` in entrypoint.sh, a run with hundreds of UA changes can be pre-empted mid-loop — the remaining UAs keep their old class until the next 24 h tick. No corruption, just slower convergence. If this becomes annoying, raise the timeout, or batch the UPDATEs.

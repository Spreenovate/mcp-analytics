# Briefing — MCP Directory Submissions (next session)

You're picking up after a session that finished the **Code-Side** of submitting mcp-analytics.com to **two** MCP directories:

1. **Anthropic Claude Connector Directory** — primary (claude.ai catalog)
2. **OpenAI ChatGPT Apps Directory** — secondary (chatgpt.com catalog)

The goal of THIS next session: **get both submissions actually filed.** No more code refactors. Just: build a small test account, write form copy, submit, wait for review.

---

## What's already done (DO NOT redo)

The CLAUDE.md "Followups" section has the rest, but for this submission specifically, all the code prep is finished as of commit `3b81f94`. Concretely:

- All 23 MCP tools have spec-correct annotations: `title`, `readOnlyHint`/`destructiveHint`/`openWorldHint`, `outputSchema` (permissive `{type: "object"}`)
- `add_site` is correctly marked as additive-only (`destructiveHint: false`)
- 5 tools that previously lacked `scope:` now have `Oauth::Scopes::READ`
- OAuth flow is spec-compliant + claude.ai-compat-tested + chatgpt-compat-prepared:
  - DCR + PKCE + RFC 8707 + RFC 9728 + RFC 9207 (we explicitly DON'T send `iss` because it broke claude.ai)
  - 302 (not 303) on consent redirect
  - `token_type: "bearer"` lowercase
  - CORS allowlist includes `claude.ai`, `chatgpt.com`, `*.openai.com`, `*.anthropic.com`, localhost
  - Path-aware discovery: both `/.well-known/oauth-authorization-server` AND `/.well-known/oauth-authorization-server/mcp` resolve (ChatGPT-strict requirement)
  - Form-action CSP relaxed on `/oauth/consent` show + decide
- Rails app pricing UI honest (Pro tier marked "Coming soon", mailto CTA, no false-promise upgrade path)
- Docs at `/docs` reflect post-Bot-Phase-2 reality (8-class taxonomy, AI-mediated browsing semantics)
- Privacy at `/privacy`, terms at `/terms`, public docs at `/docs`, logo at `/icon.svg` — all live and OK
- Bot Phase 2 traffic classification + auto-reclassify loop are deployed and running

Live state is healthy as of session end (curl `/up` → 200, `tools/list` returns 23 tools with correct annotations, `OPTIONS /oauth/token` from chatgpt.com origin → 204 with CORS).

---

## What's left to do — three blocks

### Block 1: Build the test account (Hybrid pattern A+B) 🟢 first

The user agreed on a hybrid pattern:

- **Path A (primary, no setup):** reviewer adds the connector with their own email, OAuth flow emails them a link, they click, fresh account, can call all tools. Returns valid-but-empty data on a fresh account.

- **Path B (optional, pre-seeded):** we provide a long-lived OAuth bearer for a pre-seeded demo account so the reviewer can see real-shaped data. **Spec for the demo data:**
  - **One site only** (don't over-build — we're single-user prod)
  - **~200 events** total (enough to populate `top_pages`, `top_referrers`, `breakdown`, `traffic_class_breakdown`, `engagement_overview` with non-empty results)
  - **A few days** of date coverage (e.g. 3-7 days back-dated) so `get_overview` and `get_timeseries` look interesting
  - **Mark as ephemeral** in submission notes — something like *"Demo account is reviewer-shared; data is ~200 events seeded for review and may be wiped after approval. Use your own email via OAuth for an authentic fresh account."*

#### Concrete steps for Block 1

```bash
# 1. Create the demo user via Rails runner (run from a zsh shell so kamal sources the env vars)
zsh -ic 'kamal app exec --primary "bin/rails runner \"
demo = User.create!(
  email: \\\"reviewer-demo@mcp-analytics.com\\\",
  email_verified_at: Time.current,
  plan: \\\"free\\\"
)
puts \\\"demo user id=#{demo.id} api_token=#{demo.api_token}\\\"
\""'

# 2. Add one site to the demo user
zsh -ic 'kamal app exec --primary "bin/rails runner \"
demo = User.find_by(email: \\\"reviewer-demo@mcp-analytics.com\\\")
site = demo.sites.create!(domain: \\\"demo-shop.example\\\", privacy_mode: \\\"strict\\\")
puts \\\"site_id=#{site.site_id}\\\"
\""'

# 3. Seed ~200 events into ClickHouse
# This is the tricky part — ingest writes to the events table. Either:
#  (a) Seed directly via INSERT INTO events ...  (use the schema in db/migrate or
#      query the live table for column list)
#  (b) Or fire 200 HTTP POSTs to https://t.mcp-analytics.com/event with the
#      site_id from step 2 and varied paths/UAs over the past few days. The
#      tracker accepts events via its public ingest endpoint.
# Option (b) is simpler — synthesize 200 plausible events:
#   - paths: random pick from ["/", "/pricing", "/docs", "/blog/post-1", "/about"]
#   - referrers: random pick from ["https://news.ycombinator.com", "https://twitter.com/...", "https://google.com", "" (direct)]
#   - UAs: mix of real browsers + a few crawler UAs (GPTBot, ClaudeBot) so the
#     bot-share metrics are non-zero
#   - timestamps: spread over last 3-7 days
# WARNING: the ingest endpoint may reject events if data-site is unrecognized.
# Verify the site_id is valid before bulk-firing.

# 4. Generate a read-only OAuth bearer for the demo account
zsh -ic 'kamal app exec --primary "bin/rails runner \"
demo = User.find_by(email: \\\"reviewer-demo@mcp-analytics.com\\\")
client = OauthClient.find_or_create_by!(client_name: \\\"Directory Reviewer\\\") do |c|
  c.redirect_uri_list = [\\\"https://example.com/unused\\\"]
end
token = OauthAccessToken.create!(
  user: demo,
  oauth_client: client,
  scope: \\\"analytics:read\\\",
  resource: \\\"#{ENV[\\\"PUBLIC_BASE_URL\\\"]}/mcp\\\",
  expires_at: 90.days.from_now
)
puts \\\"reviewer bearer: #{token.token}\\\"
\""'
```

After step 4 you'll have a Bearer string starting with `mcpa_oauth_…`. Save it — it goes into both submission forms.

**Verification step before moving on:**

```bash
TOKEN=<the bearer from step 4>
curl -s -X POST https://mcp-analytics.com/mcp \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"get_overview","arguments":{"site_id":"<demo-site-id>","period":"last_7_days"}}}' \
  | python3 -m json.tool
```

Should return a non-empty `get_overview` with real-ish numbers (pageviews > 0, visitors > 0, top_page populated, etc.).

---

### Block 2: Form copy 🟡 second

Both submissions need the same content. Write once, paste twice.

#### Required fields (from research notes — re-verify in actual forms)

- **Tagline** (1 line, ~80 chars): *"Web analytics you query through Claude. No dashboard. Just answers."* (already on landing page, can re-use)
- **Description** (3-5 sentences): pitch the MCP-native angle, GDPR/EU hosting, free tier, the 8-class AI-traffic taxonomy as differentiator
- **Use cases / test prompts** (3-5, each with the tool it maps to):
  1. *"How did mcp-analytics.com do yesterday?"* → `get_overview`
  2. *"Add mcp-analytics tracking to my-new-project.com"* → `add_site` + `get_tracking_snippet`
  3. *"What were my top referrers last 30 days?"* → `top_referrers`
  4. *"Which AI agents have read my docs page?"* → `top_user_agents` with traffic_class filter
  5. *"Compare last week vs the week before"* → `compare_periods`
- **Logo** — `/icon.svg` is live; check submission form for required pixel dimensions and convert if needed
- **Privacy policy URL:** `https://mcp-analytics.com/privacy`
- **Terms URL:** `https://mcp-analytics.com/terms`
- **Documentation URL:** `https://mcp-analytics.com/docs`
- **Support contact:** `info@spreenovate.de` (or set up `support@mcp-analytics.com` first if the user prefers)
- **Test credentials** — see Block 1 outcome (Path A description + Path B bearer)
- **Category:** Analytics / Developer Tools

---

### Block 3: Submit 🔴 last

#### 3a. Anthropic Claude Directory

URL: https://clau.de/mcp-directory-submission (or alternatively: email `mcp-review@anthropic.com`)

- Self-serve Google Form
- Review timeline: ~2 weeks (queue-dependent, no SLA)
- After approval: appears in claude.ai's connector catalog

Pre-submission sanity check — verify the live state:

```bash
# Discovery healthy
curl -s https://mcp-analytics.com/.well-known/oauth-authorization-server | python3 -m json.tool | head
curl -s https://mcp-analytics.com/.well-known/oauth-protected-resource | python3 -m json.tool | head

# 401 + WWW-Authenticate on unauthed /mcp
curl -s -i -X POST https://mcp-analytics.com/mcp -H "Content-Type: application/json" -d '{}' | grep -iE "^(HTTP|WWW-Authenticate)"

# Tool annotations all present
curl -s -X POST "https://mcp-analytics.com/mcp" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' \
  | python3 -c "import json,sys; t=json.load(sys.stdin)['result']['tools']; print(f'{len(t)} tools, {sum(1 for x in t if x.get(\"annotations\"))} with annotations, {sum(1 for x in t if x.get(\"title\"))} with title, {sum(1 for x in t if x.get(\"outputSchema\"))} with outputSchema')"
# Expected: 23 tools, 23 with annotations, 23 with title, 23 with outputSchema
```

#### 3b. OpenAI ChatGPT Apps Directory

URL: https://platform.openai.com/apps-manage

**HARD BLOCKER TO CHECK FIRST:** OpenAI's submission docs explicitly state *"Projects with EU data residency cannot submit apps for review."* The user runs from Germany and may have a default-EU OpenAI org. Before submitting:

1. Log into platform.openai.com
2. Check Settings → General → Data Region
3. If EU: either change to global OR create a new org with global residency for this submission specifically
4. Note the org separation does NOT change the actual server hosting (which stays in Hetzner Falkenstein) — it only affects which OpenAI tenant processes the submission metadata

Then in the dashboard:

- Identity verification
- Fill submission form (same content as Anthropic, plus the OpenAI-specific test-credentials format)
- Submit
- Review timeline: undefined per OpenAI docs ("varies as we continue to scale")
- After approval: appears in ChatGPT's app catalog visible to Plus/Pro/Business/Enterprise/Edu **without** Developer Mode toggle

---

## Things to NOT spend time on

- Don't refactor any code. The code-side audit is complete (4 audit sweeps + 2 review rounds).
- Don't touch the `?token=` legacy auth path — it's deprecation-headered and on a 6-month sunset, no urgency.
- Don't tighten outputSchema beyond `{type: "object"}` until there's a concrete reason — the permissive default is intentional defense against strict-validation surprises (see commit `3b81f94`'s message).
- Don't try to make the test account take card-payment-style logins ("non-MFA" doesn't mean "no OAuth" — see the test-account-pattern research summary).
- Don't enable Stripe / Pro-tier billing yet. Pricing UI marks Pro as "Coming soon" — that's intentional, no action needed.

---

## Followups still on the books (CLAUDE.md "Followups" section)

These are NOT for this session, but flagging in case the user prioritises:

- Phase out `?token=` query auth path entirely (~30 days after audit-log shows zero use)
- TOCTOU race in `RateLimit`/`McpRateBucket` increment-or-write pattern
- `OauthAccessToken#touch_used!` ordering vs rate-limit gate
- Reclassify auto-loop edge cases (mutation queue stacking on slow CH, scoped CH user)
- Goroutine-instead-of-shell-loop refactor in ingest

---

## Quick context cheat-sheet

- **Production host:** Hetzner Falkenstein, single CX32 (kamal deploy + accessory ingest)
- **Deploy command:** `zsh -ic 'kamal deploy'` (zsh wrapper required for `KAMAL_REGISTRY_PASSWORD` env var)
- **Live URLs:** https://mcp-analytics.com (apex Rails), https://t.mcp-analytics.com (tracker), https://mcp-analytics.com/mcp (MCP endpoint)
- **Real user count:** 1 (the operator). No paying customers yet. Pre-launch.
- **Last review verdicts:** Both Opus 4.7 + Sonnet gave SHIP on the entrypoint patch and on the auth-flip + security review followups. No outstanding Critical/High findings.

Good luck. Most of the actual submission work should fit in 2-4 hours if everything goes smoothly.

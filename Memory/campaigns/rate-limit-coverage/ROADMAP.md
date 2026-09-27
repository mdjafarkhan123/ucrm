# Roadmap — Rate-limit coverage (approved 2026-09-27)

## Origin

Memory/deferred/authenticated-reads-and-pipeline-writes-are-not-rate-limited.md.

## Verified findings (supersede the first-pass draft)

- The draft's "two shared gates" idea is wrong: signed-in API routes use ~7 different gate helpers
  (requireOrganizationPermission/Admin, requireOrganization, requireClientPermission,
  requireLinkedEntityAccess, requireContractorTeamAdmin, requireAutomationAccess, getOrganizationContext).
  The one true funnel is `src/hooks.server.ts`, which already has the user id from `getClaims()` at no cost.
- Browser data goes through `/api/*`; the browser Supabase client is used only for Realtime
  (communications page, website chat) — outside this campaign.
- `check_rate_limit` writes to a normal (logged) Postgres table: one extra DB round trip + write per check.
  Fine for the pilot, a known scaling cost on every request at full scale; Redis is already in the
  production plan and is the industry-standard home for a per-request limiter.

## Parts

1. **Front-door limit** — DONE `45127a76` (live-verified all roles + Jafar Panel; counter adds ~68 ms per
   request on managed Supabase — expected ~1 ms once DB/Redis share the VPS). Was: in `hooks.server.ts`, for `/api/*` only: per-person read bucket (GET/HEAD) and
   per-person write bucket, one check per request (GitHub/Stripe model: per-identity, reads and writes
   budgeted separately). Jafar Panel requests keyed on the owner session. Existing per-route/per-org
   buckets stay as inner limits. Limiter behind a small interface so storage can be swapped. Friendly 429
   handling in the app. Gate: unit tests, live 429 at the limit for owner + field + office roles, normal
   browsing never hits it, added latency per request measured.
2. **Unsigned-route sweep** — public token, webchat, webhook, internal-worker routes. Confirm each one's
   protection (some may live inside DB functions); fix real gaps, one-line reason for the rest.
3. **Redis storage** — blocked until the VPS/Redis exists; do as part of the production cutover.
4. **Close-out** — delete the deferred note.

## Decisions (Jafar, 2026-09-27)

- Database counter now; Redis swap (only `checkRateLimit`'s body changes) at the VPS move, failing open
  if Redis is down. When this campaign closes, move Part 3 onto crm-launch-readiness's cutover list.
- 600 reads / 120 writes per person per minute (measured normal fast browsing: ~38 API requests/min).

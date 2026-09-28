# Quote API tests never learned the rate limit

**Why it waits:** Found 2026-09-28 during deferred sweep Part 8; outside that part's scope. 70 tests across nine
`src/routes/api/quotes/**` spec files fail on a clean `main` with 500s: commit `040a2e12` ("Rate limit quote
write routes") added `checkRateLimit`, and the specs' Supabase mocks never answer it. Also failing on `main`:
`settings-business.spec.ts` (1), `resend.spec.ts` (1, already known). The routes themselves are not broken.
**Brings it back:** Any quote API work, or before trusting `npm run test:unit` as a launch gate.
**Known constraints:** Mock `$lib/server/security/rate-limit` in those specs; do not remove the rate limit.

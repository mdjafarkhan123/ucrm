# Messenger reliability — 2026-10-23

Follows the approved Messenger contract and GoHighLevel reconnect flow. Current Meta SDK source confirms the
read-only [`debug_token`](https://github.com/facebook/facebook-nodejs-business-sdk/blob/main/src/api.js) and
[`Page/subscribed_apps`](https://github.com/facebook/facebook-python-business-sdk/blob/main/facebook_business/adobjects/page.py)
endpoints. Existing researched semantics: `docs/research/messenger-transport-webhooks.md` §4–5. Meta documentation
pages returned 429 during this check; actual Graph v25 responses were also checked. Supabase changelog was fetched;
the new code uses existing Data API conditional updates, with no changed auth/RLS policy.

## Verification

- `npx vitest run src/lib/server/communications/messenger src/routes/api/webhooks/messenger`: **81 passed**.
  Includes missing/expired/wrong-app credentials, revoked permission, absent/partial subscriptions, malformed
  replies, Page error isolation and concurrency limited to three. A local mocked inbound burst offers 225
  deliveries: one wake handles 200, the next 25. Database idempotency and receipt ordering reuse Part 7's recorded
  rolled-back checks; this local burst does not measure database throughput.
- Focused Svelte/TypeScript check: **0 errors, 0 warnings**, `type-check.txt`. Full-project `npm run check` exhausted
  Node's default heap; stopped the 8 GB retry and used a focused config including the changed modules, imports,
  generated environment declarations and route. Removed an identical duplicate Messenger login-session table
  type, and added the two already-deployed echo/receipt RPC types after checking their actual database signatures.
- ESLint on changed TS/Svelte modules: passed. `git diff --check`: passed.
- Svelte autofixer: component logic passes. Its raw-SCSS pass reports false unused BEM selectors; the actual
  preprocessed styles pass Svelte check and browser rendering.
- Read-only live check against the one connected test Page: **healthy, 1,866 ms**, two Meta reads; no messages sent,
  subscriptions changed or credentials revoked.
- `database-check.txt`: migration creation and conditional updates tested inside `BEGIN`/`ROLLBACK`. One claim wins,
  the repeated claim skips, and a fresh reconnect defeats stale completion. Due query on the actual one-Page
  database: **0.048 ms**, one shared buffer. This is small-data evidence only. Repeatable rollback assertions are
  in `health-database-check.sql` (run after applying the migration).
- Browser on running branch, signed in as Raad LTD owner: real healthy Page; all three reconnect reasons through
  intercepted overview responses, 1440 and 390 widths; reconnect disables while its popup waits and shows the
  existing failure notice on failure. No real Facebook setting was changed. See `screen-check.txt` and PNGs.
  Found and fixed the existing desktop-only Settings columns, banner and Page rows on phone. Desktop appearance
  retains approved Pencil board `tEAXY`; phone stacks those same parts. No colour changes.

## Performance verdict

**Supported for the bounded implementation; service capacity not established.** Health uses the existing
one-minute cron, checks oldest due active Pages first (hourly), at most six per wake and three Graph calls at once.
Each Page requires one due-list share, one atomic claim, one token read, up to two 10-second Graph requests, and a
conditional reconnect update only on confirmed failure. The claim timestamp also backs off transient failures.
One partial `(last_checked_at NULLS FIRST, id) WHERE status='active'` index supports the due scan and idle cron
predicate. No new cache, queue, dependency or infrastructure. Health runs beside message drains; webhook
acknowledgement and direct reply wake paths do not wait for it.

The configured ceiling is 360 checks/hour per scheduled worker, **not measured capacity**. Larger Page backlogs
delay detection. Simulated six-Page concurrency is covered by tests; representative multi-tenant database load,
provider rate limits and production deployment resources remain unverified. The release performance audit owns
that evidence before public launch. Meta disabling the app-level callback while leaving the Page subscription
intact cannot be proven by this Page subscription check; Part 9/10 must verify webhook dashboard recovery before
go-live. No inference from lack of customer messages marks a Page broken. Reconnect remains an owner action.

## Integration and scheduled proof

Merged into main; combined focused type check again passed with zero errors/warnings, and all 81 Messenger tests
passed again. Migration `20270104090000_messenger_connection_health.sql` applied and recorded atomically. The first
scheduled health-only wake dispatched at **2026-10-23 07:12:00 UTC**, updated the test connection's check timestamp
at **07:12:00.581 UTC**, and left it active with no reconnect reason. The protected route returned HTTP 200 with `health: {checked: 1, reconnect: 0, deferred: 0, skipped: 0}`; no timeout. No incoming/outgoing messages were pending.
The migration version follows the concurrently merged SMS migrations; its earlier rollback-test filename differs.

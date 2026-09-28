# Jobs and Quotes list search also misses client name

- **Priority:** P2


- **Campaign:** `deferred-launch-sweep` Part 7, found incidentally 2026-09-28 while fixing the same gap on
  Requests.
- **Reason:** Not on Part 7's original list; only turned up because fixing Requests' search meant checking
  every list API for the same pattern.
- **What is wrong:** `src/routes/api/jobs/+server.ts` and `src/routes/api/quotes/+server.ts` both embed the
  client (for display) but their `search` param only matches their own columns (job title/number, quote
  title/number) — never `clients.display_name`/`company_name`. Same gap Requests had; Requests is fixed
  (`src/routes/api/requests/+server.ts`, commit `8006a42f` on `worktree-deferred-sweep-part7`).
- **Reactivation trigger:** Jafar reports the same "search by client name" gap on Jobs or Quotes, or Part 7
  resumes and picks it up as a quick add-on.
- **Prerequisites:** Copy the exact two-step shape just used in `src/routes/api/requests/+server.ts` (`GET`):
  look up matching client ids first, fold them into the existing `.or()` as `client_id.in.(...)` — same
  idiom the tag filter in `src/routes/api/clients/+server.ts` already uses.
- **Checkpoint:** `src/routes/api/jobs/+server.ts`, `src/routes/api/quotes/+server.ts`.

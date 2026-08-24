# Authenticated reads and Pipeline writes are not rate limited

- **Priority:** P1


- **Campaign:** found during `sales-pipeline` Part 2 item 3 on 2026-08-19. The fix belongs to whichever
  campaign next touches the API layer as a whole.
- **Reason:** `checkRateLimit` exists (`src/lib/server/security/rate-limit.ts`) but is only used on
  unauthenticated or sensitive routes — get-started, setup-password, the Jafar session. No authenticated
  list read in the app is limited: not Clients, not Requests, and not the Pipeline board. Adding it to the
  board alone would be inconsistent and would put an extra database round trip on every column page.
- **What is at risk:** one logged-in client looping a column page can hold pooled connections across every
  tenant. The board is capped at 50 rows a page and is keyset-paged, so a single request is cheap; the
  exposure is request volume, not request cost.
- **Also uncovered (2026-08-19):** the Pipeline write routes — owner, value, the two dates, and the Part 3A
  Task routes — carry no limit either. Each is one function call, and the Task limits cap what can be
  created, but a loop still spends connections. Same decision, same place to make it.
- **Also uncovered (2026-08-20):** the Quotes Part 2 routes join the same list -- the catalog list read and
  its create/edit writes, request pricing read and replace, the quote read, and Convert to quote. Convert is
  the one worth naming: it takes row locks on a pipeline card and a request, so a loop against it holds
  locks, not just connections.
- **Also uncovered (2026-09-01):** the two team member write routes -- the role change and the permission
  section save -- join the same list. Each is one command call behind an owner-or-admin check, so the
  exposure is volume again, not cost.
- **Reactivation trigger:** the app moves to the VPS phase, connection saturation is seen in the Supabase
  dashboard, or any campaign is already reworking the shared API guards.
- **Prerequisites:** decide with Jafar what a limited read says to the user, and pick a bucket key —
  organization plus route reads right for a shared board, per user for personal lists. Do it once for every
  list read, not per route.
- **Checkpoint:** `src/lib/server/security/rate-limit.ts`, `src/lib/server/access/permission.ts`.


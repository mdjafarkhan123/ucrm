# Part 7 — Client work overview and schedule

**Spec:** `Memory/deferred/client-work-overview-and-schedule-sections-are-empty.md`.

## What happened this session

Tried a security-definer DB function (`client_work_items`) combining requests/quotes/jobs/invoices for the
Work overview table. Built it, pushed it to the remote DB, verified it there — then found another live
session writing, in this same working directory, a different and better-fitting solution: it reuses the
*existing* `/api/requests`, `/api/quotes`, `/api/jobs`, `/api/invoices` list routes (adding a `client_id`
filter to each) instead of a new DB function, so status derivation, money-gating and permission checks stay
in the one place each already lives. That avoids a second copy of those rules. I reverted mine (dropped the
function from the remote DB, deleted the migration file, confirmed `supabase db push --linked --dry-run`
reports the remote clean) so it wouldn't sit as dead, competing code.

Also found "Client schedule" already had a fully-built, RLS-respecting backend
(`GET /api/clients/[id]/schedule`, `fetchClientSchedule`/`ClientScheduleEntry` in `$lib/clients/api.ts`) from
earlier work that was never wired into the page — not part of this note's original scope, but the fix is
just wiring it in.

## State: uncommitted, in progress in this working directory right now — not mine

As of this checkpoint, `git status` shows (uncommitted, not written by me):
- `src/lib/clients/work.ts`, `src/lib/components/clients/ClientWorkOverview.svelte`,
  `src/lib/components/clients/ClientSchedule.svelte` (new)
- `src/routes/api/clients/[id=uuid]/schedule/` (new)
- Modified: `src/lib/clients/api.ts`, `src/lib/invoices/api.ts`, `src/lib/jobs/api.ts`,
  `src/lib/quotes/api.ts`, `src/lib/requests/api.ts`, `src/lib/server/validation/jobs.schema.ts`,
  `src/lib/server/validation/quotes.schema.ts`, `src/routes/api/jobs/+server.ts`,
  `src/routes/api/quotes/+server.ts`, `src/routes/api/requests/+server.ts`,
  `src/routes/(app)/clients/[id=uuid]/+page.svelte`

This changed twice while I watched (files kept appearing/growing), so another session is actively writing
these files at the same time as this one, in the main folder rather than a worktree — against
`docs/agent-concurrency.md`'s "one writer in the main folder" rule, but real. **Do not edit any of the files
above until you have checked with Jafar or confirmed that other session has stopped.** `docs/agent-concurrency.md`:
"A dirty worktree with no matching claim may belong to another terminal. Stop and identify its owner... Never
remove or overwrite unknown changes."

## Next

1. Run `git status` fresh. If those files are unchanged from the list above and nothing is actively writing
   them, review the diff as a whole, run `npm run check` / `npx prettier --check` / `npm run test:unit` on
   the touched files, browser-verify Work overview and Client schedule on a client with real requests,
   quotes, jobs and invoices (and one with none, and one for a role without `jobs.view`/`quotes.view` to see
   the permission-limited state), then commit.
2. If still being written elsewhere, ask Jafar who owns that session before touching anything.
3. `client_work_items` must NOT be recreated — the list-route-filter approach already covers it.

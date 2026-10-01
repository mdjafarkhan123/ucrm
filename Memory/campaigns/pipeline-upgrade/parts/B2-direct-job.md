# B2 — Direct job

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` § Opportunity identity, § Outcomes
**Code:** `main`
**Done when:** A Job created from scratch shows under "Direct job" in Sales Outcomes; the board and the
Request/Quote conversion numbers do not change.

## Steps

- [x] Research: nothing recorded a from-scratch Job in the Pipeline; 15 such Jobs already exist in the test data
- [x] Migration written: saving a from-scratch Job writes one closed-only Direct job record with the Job total
      frozen; older from-scratch Jobs get theirs; Sales Outcomes reads split Won, Lost, and Direct job
- [ ] Apply the migration and update `src/lib/database.types.ts`
- [ ] Sales Outcomes page: "Direct job" in the Type list (`src/lib/pipeline/outcomes.ts`,
      `src/routes/(app)/pipeline/outcomes/+page.svelte`)
- [ ] Financial sales-outcomes report and export name Direct jobs and keep them out of Won
      (`src/routes/api/reports/financial/sales-outcomes/+server.ts`, `src/lib/server/exports/financial-export.ts`)
- [ ] The inbox side panel's Pipeline list leaves Direct jobs out (`src/lib/server/communications/conversation-context.ts`)
- [ ] Tests, then browser check of the done-check
- [ ] Jobs plan (`docs/jobs-behavior-contract.md` § Identity) gets one Direct job line

## Next

Apply `supabase/migrations/20261002100000_direct_job_is_won.sql` (`npx supabase db push --linked`, dry-run
first), then build the page and report steps above.

## Outside actions

- Database migration `20261002100000` — check: `npx supabase migration list --linked` shows it in the Remote
  column — pending

## Notes

- Decision: Direct jobs are their own Type in Sales Outcomes, not mixed into the Won list, and are not in the
  board's Won tile. That is what "reported separately" and "the board does not change" ask for.
- A from-scratch Job with nothing priced on it is a Direct job that is **Unvalued**, not $0. The migration also
  fixes B1 here: a Job holding only text lines used to count as $0.
- Deleting a Job (only through deleting its property) removes its Direct job record with it.

# B1 — Request straight to a Job is Won

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` § Opportunity identity, § Outcomes
**Code:** `main`
**Done when:** Converting a Request to a Job creates the Job, the card leaves the board, and the Won tile
rises by one with the Job's total; making a Job from an already-Won Quote adds nothing.

## Steps

- [x] Research: "Convert to job" on the Request page was only a greyed-out menu item; nothing existed behind it
- [x] Migration written: a Job remembers its Request, and saving the Job marks the Request Converted and its
      card Won with the Job total
- [ ] Apply the migration and regenerate `src/lib/database.types.ts`
- [ ] `/api/jobs` accepts the source Request; the New Job page opens filled in from `?request=<id>`
- [ ] Request page: "Convert to job" enabled; a converted Request links to its Job
- [ ] Tests, then browser check of the done-check (board, Won tile, Quote-to-Job adds nothing)
- [ ] Jobs plan (`docs/jobs-behavior-contract.md` § Identity) gets the Request-lineage line, with Jafar's approval

## Next

Apply `supabase/migrations/20261002090000_request_to_job_is_won.sql` (`npx supabase db push --linked`, dry-run
first), then build the API and page steps above.

## Outside actions

- Database migration `20261002090000` — check: `npx supabase migration list --linked` shows it in the Remote
  column — pending

## Notes

- Method followed: Jobber. "Convert to Job" opens the ordinary New Job form filled in from the Request; the
  Request becomes Converted only when that Job is saved.
- A Job saved with no priced lines makes the card Won but **Unvalued**, not $0.
- The Request's line photos carry to the Job; the Job must stay with the Request's client.

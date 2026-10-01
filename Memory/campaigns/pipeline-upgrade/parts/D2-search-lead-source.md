# D2 — Search, lead source, and New button

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` § First-release board
**Code:** worktree `.claude/worktrees/pipeline-d2`, branch `worktree-pipeline-d2`
**Done when:** Typing a phone number finds its card; filtering by one lead source shows only those cards and
the column counts and totals agree

## Steps

- [x] Performance design: no new index; search filters the open cards the board already reads
- [x] Database change written and trial-run with 5,000 pretend open cards, then rolled back
- [x] Apply the database change for real
- [x] API routes and filter vocabulary take `q` (search) and `source` (lead source)
- [x] Search box and Lead source pill in the control bar; lead source chip on the card
- [x] New request / New quote buttons in the page header (New quote only for people who may make quotes)
- [ ] Lead source ignores case and lists the sources clients really carry (`20261003090000`)
- [ ] Tests, `npm run check`, browser check of the done-check
- [ ] Merge to `main`, performance verification note, close the part

## Next

Apply `20261003090000` with `npx supabase db push --linked` from the worktree, then add
`/api/pipeline/lead-sources` and load it in the Lead source pill on hover. Then browser check on port 5180.

## Outside actions

- Migration `20261002233000` — applied (remote ledger shows it)
- Migration `20261003090000` — check: `supabase migration list --linked` shows remote `20261003090000`, and
  `public.pipeline_lead_sources` exists — pending

## Notes

- This note lives on the branch until the merge: a worktree session cannot write the main folder.
- The other session took `20261002220000` for Support Messenger; this part's file is `20261002233000`.
- The new functions still answer calls that name only the old arguments, so the database change is safe to
  apply before the code reaches `main`.
- Lead sources are free text: test data has "Referral", "referral", "Google", "staff". Tidying them
  everywhere (Marketing groups match exactly too) is outside this part — defer it.
- Requests have no number in UCRM, so search covers the Quote number only. Tell Jafar.
- Trial timing at 5,000 open cards in one organization (2,000 in one column): a search that matches
  nothing took about 140 ms per column and 72 ms for the counts. It grows with open cards, so about
  20,000 open cards in one organization is where it would need a rethink.

# C1 — Home: today's next actions

**Campaign:** jafar-business-management · **Plan:** `docs/jafar-business-management-behavior-contract.md` § 6. Know what to do today, § Speed
**Code:** `main`
**Done when:** An overdue follow-up shows at the top; completing it removes it

## Steps

- [x] Layout and old-numbers decisions from Jafar (see Notes)
- [ ] Migration `owner_business_home` + due index, applied to remote and renamed to its version
- [ ] `GET /api/jafar/home` (per-tile access checks, browser's date) + spec
- [ ] Home page in `src/routes/jafar/(protected)/+page.svelte`; Done reuses `NextActionDialog`; home key invalidated by `refreshLead`/`refreshDeals`
- [ ] Onboarding and Applications pages read their filter from the tile link (`?waiting_on=uplift`, `?stage=payment_confirmed`)
- [ ] Performance verification (large test data) and browser test of the done-check

## Next

Apply `supabase/migrations/uplift_business_home.sql` with the Supabase MCP, then rename the file to the version it got.

## Outside actions

- Apply migration `uplift_business_home` — check: `select to_regprocedure('public.owner_business_home(date,integer)')` is not null — pending

## Notes

Jafar, 2026-10-07: layout is counters on top ("Waiting on you": to review, first contacts, accounts to create, setups waiting on Uplift, renewals due) then one to-do list Overdue → Today → Next 7 days, each row with a tag and Done. Keep unread alerts on the home; drop the organisation counts (they live on Organizations). Replies have no inbox yet: an Interested Deal's "Reply to …" step stands in. Call hours arrive with C2.
Speed design: one request; list capped at 60 with totals per bucket and a link to Leads sorted by next action; partial index on (next_action_due_on, id). Assumed up to 20k businesses, 2k organisations.

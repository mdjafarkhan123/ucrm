# C1 — Home: today's next actions

**Campaign:** jafar-business-management · **Plan:** `docs/jafar-business-management-behavior-contract.md` § 6. Know what to do today, § Speed
**Code:** `main`
**Done when:** An overdue follow-up shows at the top; completing it removes it

## Steps

- [x] Layout and old-numbers decisions from Jafar (see Notes)
- [x] Migrations `20261007162236_uplift_business_home` and `20261007163244_uplift_business_home_paid_only` applied to remote (check: `select to_regprocedure('public.owner_business_home(date,integer)')` not null)
- [x] `GET /api/jafar/home` + spec; home page; Done reuses `NextActionDialog`; `refreshLead`/`refreshDeals` invalidate `jafarHomeKey`
- [x] Onboarding and Applications pages read the tile's filter from the URL
- [x] Browser test `src/routes/jafar/home.e2e.ts` passed (done-check)
- [x] Polish: tiles draw at once, phone swipe row, Done keeps its spinner until the home reloads
- [ ] Performance verification branch with large test data; then mark C1 done, point NOW at C2

## Next

`performance-review` verification branch: seed thousands of test Leads with next actions (tag them so they can be deleted; record the tag here before seeding), time `owner_business_home` with EXPLAIN and the home route on a slowed phone profile, delete the seed and confirm none remain. Run the browser test as `npx playwright test "$PWD/src/routes/jafar/home.e2e.ts"` — a bare path also matches copies inside `.claude/worktrees/`, which then collide on the shared test business.

**Seed in progress (2026-10-08):** fake Leads carry `source_detail = 'perf-seed-c1-20261008'`. Check: `select count(*) from platform_business_relationships where source_detail = 'perf-seed-c1-20261008'` — must end at 0; delete them (their Deals cascade) if any remain.

## Notes

Jafar, 2026-10-07: layout is counters on top ("Waiting on you": to review, first contacts, accounts to create, setups waiting on Uplift, renewals due) then one to-do list Overdue → Today → Next 7 days, each row with a tag and Done. Keep unread alerts on the home; drop the organisation counts (they live on Organizations). Replies have no inbox yet: an Interested Deal's "Reply to …" step stands in. Call hours arrive with C2. Home stays Jafar-only (no area claims `/jafar` or `/api/jafar/home`); D3 gives teammates theirs. Known gap: the First contacts tile links to all Approved Leads (sorted by next action), so the list can include ones already contacted.
Speed design: one request; list capped at 60 with totals per bucket and a link to Leads sorted by next action; partial index on (next_action_due_on, id). Assumed up to 20k businesses, 2k organisations.

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
- [x] Speed check at 20k Leads / 6k due this week (seed deleted, 0 left): home SQL 23 ms; phone slow-4G LCP ≤0.5 s, CLS 0.008, Done dialog ≈0.2 s
- [x] Fix the slow "Setups waiting" count: migration `20261008003000_uplift_onboarding_list_hidden_fence` (check: function body contains `offset 0`); ~1.9 s → ~0.1 s, answers unchanged
- [ ] Find out what the 264 requests on a cold home load are; fix any waste

## Next

Trace the 264 requests on a cold home load (production build, not dev) and remove any that aren't needed. Then mark C1 done and point NOW at C2. Work happens in worktree `../Ucrm-wt-jafar-c1`, branch `jafar-c1-speed`; remove both when C1 is done.

## Notes

Jafar, 2026-10-07: layout is counters on top ("Waiting on you": to review, first contacts, accounts to create, setups waiting on Uplift, renewals due) then one to-do list Overdue → Today → Next 7 days, each row with a tag and Done. Keep unread alerts on the home; drop the organisation counts (they live on Organizations). Replies have no inbox yet: an Interested Deal's "Reply to …" step stands in. Call hours arrive with C2. Home stays Jafar-only (no area claims `/jafar` or `/api/jafar/home`); D3 gives teammates theirs. Known gap: the First contacts tile links to all Approved Leads (sorted by next action), so the list can include ones already contacted.
Speed design: one request; list capped at 60 with totals per bucket and a link to Leads sorted by next action; partial index on (next_action_due_on, id). Assumed up to 20k businesses, 2k organisations.

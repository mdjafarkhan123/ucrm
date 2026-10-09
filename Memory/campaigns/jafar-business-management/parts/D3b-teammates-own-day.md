# D3b — Teammates' own day

**Campaign:** jafar-business-management · **Plan:** `docs/jafar-business-management-behavior-contract.md` § 6 and § Team access
**Code:** `main`
**Done when:** Sam's home and calendar show only his Lead and call; Jafar's Everyone switch shows it too

## Steps

- [x] Database: `supabase/migrations/20261109090000_uplift_teammate_day.sql` (teammate time zone and reminder defaults; reads take the viewer; Jafar's home `everyone`; Busy blocks personal)
- [x] Server: home and calendar routes scoped by the session (`$lib/server/jafar/calendar.ts` `calendarViewer`); home, calendar and My preferences open to every signed-in person (`$lib/jafar/team-access.ts`); teammates land on `/jafar`
- [x] Screens: home (own greeting, tiles they may open, Mine/Everyone for Jafar, Done only with Leads change), calendar (no "Book a call" without Leads change), sidebar "My preferences" for teammates
- [x] Apply the migration; update unit tests (`team-access.spec.ts` teammateHomePath, `api/jafar/home/home.spec.ts`)
- [x] Sam in the browser: home (only his Lead and call, First contacts tile only, Call tag), calendar (only his call), My preferences (his own zone) — desktop and phone. Speed: same due index plus an owner filter; home 7 ms, 6-week calendar 11 ms on live data
- [ ] Jafar in the browser: Mine hides Sam's call, Everyone shows it with "Sam Seller"; desktop and phone
- [ ] Commit, push, mark Done

## Next

Browser proof is mostly done (2026-10-09): Sam's home and calendar show only his Lead and call; Jafar's Mine hides it and Everyone shows it with "Sam Seller". Left to do:
1. Retake the screenshots with one sign-in per person (the sign-in limit blocks repeated logins). Check the phone header fix in `src/routes/jafar/(protected)/+page.svelte` (title stays on one line, Mine/Everyone moves underneath on a phone; not yet seen).
2. The same call showed a "Follow-Up" tag on desktop and "Call" on the phone in the first round. `agendaTag` should give "Call". See whether it happens again.
3. The 50k-Lead speed check (plan § Speed), then commit, push, mark Done.
4. Clean up the test data: cancel test call `533491fe-143e-40a3-9a25-1c0aca0c78b7` on A1 Test Roofing (`9762d6ac-…`) and put back its old next step, "Try again after their busy season", due 2026-10-09.

## Outside actions

- Apply migration 20261109090000 (uplift_teammate_day) — check: it appears in the project's migration list and `owner_business_home` takes four arguments — done (verified 2026-10-09)

## Notes

- Jafar said no type check is needed this session (2026-10-09).
- Calendar has no Everyone switch: the approved part names it for the home only.

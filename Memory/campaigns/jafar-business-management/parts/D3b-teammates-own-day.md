# D3b — Teammates' own day

**Campaign:** jafar-business-management · **Plan:** `docs/jafar-business-management-behavior-contract.md` § 6 and § Team access
**Code:** `main`
**Done when:** Sam's home and calendar show only his Lead and call; Jafar's Everyone switch shows it too

## Steps

- [x] Database: `supabase/migrations/20261109090000_uplift_teammate_day.sql` (teammate time zone and reminder defaults; reads take the viewer; Jafar's home `everyone`; Busy blocks personal)
- [x] Server: home and calendar routes scoped by the session (`$lib/server/jafar/calendar.ts` `calendarViewer`); home, calendar and My preferences open to every signed-in person (`$lib/jafar/team-access.ts`); teammates land on `/jafar`
- [x] Screens: home (own greeting, tiles they may open, Mine/Everyone for Jafar, Done only with Leads change), calendar (no "Book a call" without Leads change), sidebar "My preferences" for teammates
- [x] Apply the migration; update unit tests (`team-access.spec.ts` teammateHomePath, `api/jafar/home/home.spec.ts`)
- [ ] Prove it as Sam and Jafar in the browser (design screen check, desktop and phone); speed check at 50k Leads
- [ ] Commit, push, mark Done

## Next

Prove it as Sam and Jafar in the browser (design screen check, desktop and phone), then the 50k-Lead speed check.

## Outside actions

- Apply migration 20261109090000 (uplift_teammate_day) — check: it appears in the project's migration list and `owner_business_home` takes four arguments — done (verified 2026-10-09)

## Notes

- Jafar said no type check is needed this session (2026-10-09).
- Calendar has no Everyone switch: the approved part names it for the home only.

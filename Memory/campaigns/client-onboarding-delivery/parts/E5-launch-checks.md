# E5 — Launch checks

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §6 (E5 choices)
**Code:** `main`
**Done when:** A pending item cannot show as complete; Ask for launch approval waits for the checklist

## Steps

- [x] Jafar's choices recorded in the plan (hand ticks with Doesn't apply; open waits named, never block; approver sees a summary; each version has its own list)
- [x] Migration `20261103090000_setup_launch_checks.sql`: per-version checks table, owner tick/untick command, Ask refuses until the list is done and keeps a snapshot on the request, link page returns it; push to dev; types
- [x] `$lib/setup/launch-checks.ts` (lines per package, linked waits, done rule) + spec
- [x] Jafar's API route and Launch checks panel above Launch approval; Ask waits for it
- [x] Approver summary on the Setup page card and the link page
- [ ] Browser check on Raad LTD, remove test data

## Next

Browser check (step 6) on Raad LTD. Raad's package has no services, so only the four everyone-lines show; to see a
waiting line, add a test wait/package by SQL and remove it after (test rows use `t@example.com`/`browser-check@example.com`).
Needs a released preview: release one on Jafar's Setup tab, tick lines, Ask, open the link page and the client Setup
card, then delete the test preview, checks and request.

## Outside actions

- Migration applied to dev — check: `select 1 from supabase_migrations.schema_migrations where version = '20261103090000'` — done

## Notes

Lines: web address and padlock, phone look, test form → lead (website); calls/missed-call/replies, STOP/HELP
(calls_texting); emails arrive, imports add up, client owns accounts, everything else works (everyone).
Checks for a version freeze once a request exists for it.

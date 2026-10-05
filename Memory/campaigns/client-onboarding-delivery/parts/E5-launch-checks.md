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

Jafar's side checked in Chrome on 2026-10-05: tick, Doesn't apply dialog, Undo, "N left", Ask locked then unlocked,
list frozen after the request, and the link page summary all look right (two small look fixes committed).
**Left:** the client owner's Setup card summary. Test data is LIVE on Raad now: Ready row, released preview v1,
`google_profile` wait, 4 checks, and an approval request made by SQL (no email). Jafar signs in as the contractor
owner, then open `/setup` and look for "What Uplift checked before asking". Then delete Raad's preview v1 (cascades
checks and request), the `google_profile` wait and the Ready row (all `browser-check@example.com`); confirm counts
are 0. Then close E5.

## Notes

Lines: web address and padlock, phone look, test form → lead (website); calls/missed-call/replies, STOP/HELP
(calls_texting); emails arrive, imports add up, client owns accounts, everything else works (everyone).
Checks for a version freeze once a request exists for it.

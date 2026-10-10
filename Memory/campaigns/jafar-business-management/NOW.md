# Jafar Business Management — now

**Goal:** Jafar and his team can run Uplift's complete lead-to-client journey in `/jafar`, through researched product behavior, premium UI/UX, working software, tests, and final desktop and mobile approval.
**Plan:** `docs/jafar-business-management-behavior-contract.md`

**Next:** Stage F (`stages/F-finish.md`). E4a, E4b and E5 are built (2026-10-10). The live checks for Zoom and Google Meet wait on Jafar's own app settings in `.env` (names in `.env.example`; Google's consent screen must be published). Run the booking e2e files with `--workers=1` on a production build with a longer webServer timeout. Every screen part runs the `performance-review` design branch first and verification before Done (plan § Speed); the slow first visit to any `/jafar` page is app-wide (`Memory/deferred/jafar-first-visit-waits-for-app-download.md`). Chrome cannot reach this computer's localhost: use Playwright screenshots. More than 10 test sign-ins in 15 minutes locks the login.

**Blockers:** none. Product behavior and first-release scope are approved; full Uplift mailboxes and automated first-contact email remain later-release work.

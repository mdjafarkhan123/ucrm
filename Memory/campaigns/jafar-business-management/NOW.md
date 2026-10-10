# Jafar Business Management — now

**Goal:** Jafar and his team can run Uplift's complete lead-to-client journey in `/jafar`, through researched product behavior, premium UI/UX, working software, tests, and final desktop and mobile approval.
**Plan:** `docs/jafar-business-management-behavior-contract.md`

**Next:** E4b Zoom connection, then E5 (`stages/E-booking.md`), then F. E4a (Zoom meeting types and links the host adds) is done (2026-10-10). E4b's live proof needs Jafar's own Zoom Marketplace app; the code can be built and tested against a stand-in first. The booking e2e build takes over Playwright's 60 s wait: build first, then run with a config whose webServer is `npm run preview` with a longer timeout. Every screen part runs the `performance-review` design branch first and verification before Done (plan § Speed); a first visit to any `/jafar` page waits about 5 s for the app download on a slow phone — that is app-wide, recorded in `Memory/deferred/jafar-first-visit-waits-for-app-download.md`, not a part's to fix. Chrome cannot reach this computer's localhost: screen checks use Playwright screenshots. Test runs sign in as Jafar; more than 10 sign-ins in 15 minutes locks the login.

**Blockers:** none. Product behavior and first-release scope are approved; full Uplift mailboxes and automated first-contact email remain later-release work.

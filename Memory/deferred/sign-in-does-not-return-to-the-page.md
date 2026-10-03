# Signing in does not return to the page you came from

**Why it waits:** Outside onboarding D5b. A signed-out person who opens any CRM link — such as an unseen-reply
email's Open chat button (`/dashboard?support_chat=<id>`) — signs in and lands on the dashboard without the
chat opening. Signed-in people are unaffected.
**Brings it back:** Pre-launch sign-in polish, or Jafar asking for it.
**Known constraints:** `requireContractor` (`src/lib/server/auth/guards.ts`) redirects to bare `/login`. The
return address must be checked as a same-site path so it cannot send people to another website.

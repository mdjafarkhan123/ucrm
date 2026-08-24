# The get-started page ships a 7.9 MB client chunk

- **Priority:** P3


- **Campaign:** none - found during the `quotes` Part 5C page-weight check, 2026-08-21.
- **Reason:** `/get-started` builds to `nodes/34.*.js` at 7.9 MB, roughly sixty times the next largest route
  chunk. It is outside Quotes, so it was not touched. Nothing else in the app is close to it, which points
  at one bundled dataset rather than page code.
- **Reactivation trigger:** anyone works on onboarding or sign-up, or a real first-visit measurement is taken.
- **Prerequisites:** find what the chunk actually contains, then move it behind a server route or a dynamic
  import.
- **Checkpoint:** `.svelte-kit/output/client/_app/immutable/nodes/34.*.js` after `npm run build`, and the
  `/get-started` route.


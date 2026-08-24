# The Get started page ships an 8 MB chunk

- **Priority:** P3


- **Campaign:** none — found 2026-08-20 during the performance review of the New Request page, unrelated to it.
- **Reason:** `src/lib/components/ui/LocationPicker.svelte` imports `country-state-city`, which bundles every
  country, state and city in the world into the browser chunk. `/get-started` (node 31) builds to **8.1 MB**;
  the next largest route chunk in the whole app is 131 kB. A first visit blocks on that download before the
  page can paint anything, and this is the signup page, so it is the first thing a new customer waits on.
- **The likely fix:** stop shipping the dataset. Either serve country/city lookups from an API route backed by
  a table, or `import()` the package only once the city field is actually focused. The route-level fix is the
  better one; the dynamic import is the cheap one.
- **Reactivation trigger:** any work on `/get-started`, onboarding, or `LocationPicker`, or before the first
  real signups.
- **Checkpoint:** `src/lib/components/ui/LocationPicker.svelte`, `package.json` (`country-state-city`),
  `.svelte-kit/output/client/_app/immutable/nodes/31.*.js`.


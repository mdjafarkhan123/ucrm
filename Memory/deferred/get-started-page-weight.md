# `/get-started` page weight

- **Priority:** P3

- **Campaign:** `jafar-panel` (the signup route feeding Prospects). Found during `clients-properties`.
- **Reason:** Jafar deferred the work on 2026-08-17, right after it was found. Nothing depends on it yet.
- **What is wrong:** `/get-started` builds to a roughly 8 MB client chunk (measured 8.2, 8.1 and 7.9 MB on three separate days; the next largest route chunk is about 131 kB) — by far the heaviest page in the app,
  and it is the public signup entry point, hit by people on phones and poor connections. The weight comes
  from `src/lib/components/ui/LocationPicker.svelte` importing `country-state-city`, which ships every
  country, state, and city on earth into the browser bundle. `TimezonePicker` on the same page is fine.
- **Reactivation trigger:** Jafar asks to optimize signup, real signups are reported as slow, or any other
  page starts using `LocationPicker` and inherits the same weight.
- **Prerequisites:** Decide with Jafar how city lookup should work first, because that is a product call,
  not just a build one. Options to put to him: search cities through a server route so nothing ships to the
  browser (the proper fix); `import()` the package only when the city field is focused (the cheap one); ship only the countries the product sells in; or drop the picker to plain typed fields. Then
  re-run `npm run build` and check the chunk under
  `.svelte-kit/output/client/_app/immutable/nodes/` to confirm the drop.
- **Also imports it:** `src/routes/(app)/settings/business-profile/+page.svelte` (`Country` only, so lighter).
- **Checkpoint:** `src/lib/components/ui/LocationPicker.svelte` and `src/routes/get-started/+page.svelte`.


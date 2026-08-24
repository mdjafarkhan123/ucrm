# `/get-started` page weight

- **Priority:** P3


- **Campaign:** `jafar-panel` (the signup route feeding Prospects). Found during `clients-properties`.
- **Reason:** Jafar deferred the work on 2026-08-17, right after it was found. Nothing depends on it yet.
- **What is wrong:** `/get-started` builds to an 8.2 MB client chunk — by far the heaviest page in the app,
  and it is the public signup entry point, hit by people on phones and poor connections. The weight comes
  from `src/lib/components/ui/LocationPicker.svelte` importing `country-state-city`, which ships every
  country, state, and city on earth into the browser bundle. `TimezonePicker` on the same page is fine.
- **Reactivation trigger:** Jafar asks to optimize signup, real signups are reported as slow, or any other
  page starts using `LocationPicker` and inherits the same weight.
- **Prerequisites:** Decide with Jafar how city lookup should work first, because that is a product call,
  not just a build one. Options to put to him: search cities through a server route so nothing ships to the
  browser; ship only the countries the product sells in; or drop the picker to plain typed fields. Then
  re-run `npm run build` and check the chunk under
  `.svelte-kit/output/client/_app/immutable/nodes/` to confirm the drop.
- **Checkpoint:** `src/lib/components/ui/LocationPicker.svelte` and `src/routes/get-started/+page.svelte`.


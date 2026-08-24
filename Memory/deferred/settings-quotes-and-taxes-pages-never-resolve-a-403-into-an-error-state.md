# Settings Quotes and Taxes pages never resolve a 403 into an error state

- **Priority:** P3

- **Campaign:** found during `contractor-settings` Part 2C closing browser verification (permission-denial
  check), 2026-08-24.
- **Reason:** Not 2C's scope — the loading-state pattern is shared across every Settings section page, not
  introduced by Quote Settings; Taxes (2A, already closed) has the identical gap. Fixing it means touching a
  shared loading/error pattern used by every `settings/*` page, which is bigger than one part.
- **What is wrong:** `GET /api/settings/quotes` and `GET /api/settings/taxes` both correctly return 403 for
  the `field` role (confirmed via direct network inspection — no data leaks), but `/settings/quotes` and
  `/settings/taxes` leave the page in a permanent loading/skeleton state instead of showing an error. Price
  Book (`/settings/price-book`) is better — it eventually shows a generic "Something went wrong / could not
  be loaded / Try Again" panel after TanStack Query exhausts its retries — but Quotes and Taxes never reached
  that state even after several seconds of observation. Same bug class as
  [`quotes-list-page-never-resolves-a-403-into-an-error-state`](quotes-list-page-never-resolves-a-403-into-an-error-state.md),
  a different area of the app.
- **Reactivation trigger:** any campaign next touches a Settings page's data-loading/error pattern, or a real
  non-owner/admin member reports a Settings page hanging.
- **Prerequisites:** none — copy whatever error-state pattern Price Book (or the Quotes detail page) already
  uses, and apply it consistently across all `settings/*` pages in one pass rather than one at a time.
- **Checkpoint:** `src/routes/(app)/settings/quotes/+page.svelte`, `src/routes/(app)/settings/taxes/+page.svelte`,
  `src/routes/(app)/settings/price-book/+page.svelte` (as the working reference).

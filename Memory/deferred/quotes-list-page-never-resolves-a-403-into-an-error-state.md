# Quotes list page never resolves a 403 into an error state

- **Priority:** P3


- **Campaign:** found during `quotes` Part 6B closing browser verification, 2026-08-21.
- **Reason:** Not 6B's scope — the list page's data loading belongs to earlier Quotes parts, and the bug only
  surfaced because 6B needed a `field`-role member (who has no `quotes.view`) to verify the deposit
  permission split live.
- **What is wrong:** `GET /api/quotes` and `GET /api/quotes/counts` both correctly return 403 for a member
  without `quotes.view`, but `/quotes` (`src/routes/(app)/quotes/+page.svelte`) leaves the row skeletons
  spinning forever instead of showing an error state. The single quote detail page
  (`src/routes/(app)/quotes/[id]/+page.svelte`) already handles this correctly — it shows "Something went
  wrong / That quote could not be loaded."
- **Reactivation trigger:** any campaign next touches the Quotes list page's data loading, or a real
  `field`/other quotes-blind member reports the list hanging.
- **Prerequisites:** none — copy the same error-state pattern the detail page already uses.
- **Checkpoint:** `src/routes/(app)/quotes/+page.svelte`.


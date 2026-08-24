# The Pipeline nav item is not gated on entitlement or permission

- **Priority:** P1


- **Campaign:** `sales-pipeline` Part 1, 2026-08-18. Belongs to whichever campaign next gives the app shell
  a real access context.
- **Reason:** Part 1's checklist asked for the nav item to appear only for members with the
  `sales.pipeline` entitlement and `pipeline.view`. The shell has no access context to decide that with:
  `src/routes/(app)/+layout.server.ts` loads membership only, and the nav in `AppShell.svelte` is a static
  array. The one available answer is `resolveOrganizationAccess`, which costs ~400 ms — and putting it in
  the layout load would charge that to **every** page in the app, not just the gated ones.
- **What ships instead:** the nav item is a normal link, and `/pipeline` itself renders the honest
  unavailable state. A refused member sees "Pipeline is not part of your plan" or "You do not have access
  to the pipeline" — different words for the two 403 reasons — and no counts or records leak either way.
  The refusal is real; only the nav item is unconditioned.
- **Reactivation trigger:** the access resolver gets its cache (see the entry above), or any campaign adds
  a per-feature access context to the app shell. Do it once, for every gated area, not for Pipeline alone.
- **Prerequisites:** the resolver caching decision has to land first, or this trades a correct nav item for
  400 ms on every page load.
- **Checkpoint:** `src/lib/components/layout/AppShell.svelte`, `src/routes/(app)/+layout.server.ts`,
  `src/routes/(app)/pipeline/+page.svelte`.


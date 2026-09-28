# `resolve()` route union type is too complex to represent (TypeScript)

**Why it waits:** `npm run check` (found 2026-09-28, first successful full run this campaign — earlier runs
crashed with an out-of-memory error before reaching this) reports "Expression produces a union type that is
too complex to represent" for three `resolve()` calls: `src/lib/components/pipeline/OpportunityBriefDrawer.svelte:92`,
`src/routes/(app)/+layout.svelte:126`, `src/routes/(app)/invoices/new/+page.svelte:350`. This is TypeScript's
inference limit on SvelteKit's generated route-id union, reached as the app's route count grew — not traced to
one commit and not caused by any single feature's code. Compile-time only; the pages work at runtime.

**Brings it back:** whenever `npm run check` needs to be clean again, or as part of Part 8 (Speed/tech-debt) —
likely needs splitting the route-id union or typing `resolve()` calls more narrowly, not a one-line fix.
**Known constraints:** more routes will keep pushing this further; a fix should check whether the union is
inherently this large or whether some route group can be narrowed before `resolve()` sees it.

# Data and Cache Architecture: Current Checkpoint

## Goal

Establish predictable TanStack Query ownership before broader hydration, cached navigation, invalidation, or
Realtime behavior.

## Current part

Part 2 closed (uncommitted, 2026-09-27): Jafar Panel now has a `src/lib/jafar/query-keys.ts` factory (was 88
hand-typed `['jafar', ...]` literals across ~40 files); every other domain already had this convention. Also
added a `queryClient.clear()` on sign-out (`AppShell.svelte`), closing a same-tab cross-session cache leak
found during the inventory. `npm run check`, prettier, and a new `query-keys.spec.ts` (7 tests) all pass.

Part 3 (Safe hydration and cached navigation) is next, dependency-ready.

## Exact next action

Ask Jafar whether to start Part 3 now or stop here for this session. If starting Part 3: inventory current
SSR/CSR boundaries and loading-state handling before proposing changes (same pattern as Part 2).

## Blockers

None. Part 2's code changes are uncommitted — confirm with Jafar before committing.

## Completion gate

Part 3: shell stays immediate while cached data revalidates in the background.

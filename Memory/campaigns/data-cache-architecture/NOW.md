# Data and Cache Architecture: Current Checkpoint

## Goal

Establish safe, predictable TanStack Query ownership before broader hydration, cached-navigation, invalidation, or Realtime behavior is added.

## Status

Paused. Part 1 is complete; Part 2 is the next approved slice.

## Active part

Part 2, shared query-key conventions.

## Exact next action

When resumed, inventory current query keys and every invalidation caller, group them by real server-state ownership, and propose the smallest shared key factory before editing code.

## Blockers

None. Resume deliberately before adding broader cache or Realtime behavior.

## Protected work

Preserve unrelated query, route, and component changes already present in the dirty worktree.

## Required pointers

- `AGENTS.md` engineering rule 5.
- `src/lib/query-client.ts` and `src/routes/+layout.svelte` for current client ownership.
- Current `createQuery`, `createMutation`, `useQueryClient`, and invalidation call sites discovered with `rg`.
- `Memory/campaigns/data-cache-architecture/ROADMAP.md`.
- `Memory/campaigns/data-cache-architecture/parts/02-query-key-conventions.md`.

## Verified baseline

The module-level QueryClient singleton was replaced with a per-layout instance, and mutating pages read it from provider context. Verify this against current code when resuming rather than trusting Memory alone.

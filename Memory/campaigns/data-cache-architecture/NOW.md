# Data and Cache Architecture: Current Checkpoint

## Goal

Establish predictable TanStack Query ownership before broader hydration, cached navigation, invalidation, or Realtime behavior.

## Current part

Paused. Part 1 is closed; Part 2 query-key conventions is the next approved slice.

## Exact next action

When resumed, execute parts/02-query-key-conventions.md: inventory current keys and invalidations, then propose the smallest shared key family before implementation.

## Blockers

None; deliberately paused.

## Completion gate

Every current query and invalidation maps to a stable, tenant-safe key family.

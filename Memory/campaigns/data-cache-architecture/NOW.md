# Data and Cache Architecture: Current Checkpoint

## Goal

Establish predictable TanStack Query ownership before broader hydration, cached navigation, invalidation, or
Realtime behavior.

## Current part

Part 3 closed (uncommitted, 2026-09-27): audited SSR/CSR boundaries and loading-state handling against the
CLAUDE.md caching rule. Found already-compliant: page-level `load` functions, the skeleton pattern on 11/12
sampled pages, dialog/tab hover-prefetch on the sampled contractor components, `resolve()` route-id usage.
Fixed: 10 routinely-used routes missing from the shell's warm list (`src/routes/(app)/+layout.svelte`, most
notably quote detail and payment detail), and the dashboard's one-off inline skeleton markup (now uses the
shared `LoadingSkeleton` component). Confirmed the Pipeline board's per-column skeleton was already correct
(the earlier grep-based scan missed `PipelineColumn.svelte`'s own `query.isPending` handling — not a real gap).
Jafar deferred two related but distinct improvements to `Memory/deferred/INDEX.md`: Jafar Panel org-detail
tabs have no hover-prefetch, and list-page table rows use `goto()` instead of real links (loses per-row hover
data-prefetch). `npm run check` and prettier pass on the touched files; Chrome extension wasn't connected this
session, so the dashboard skeleton swap has not been browser-verified — worth a quick look before/at commit.

Part 4 (Targeted invalidation and justified Realtime) is next, dependency-ready.

## Exact next action

Ask Jafar whether to start Part 4 now or stop here for this session. If starting Part 4: inventory current
invalidation completeness (known gaps already found in Part 2's inventory, e.g. invoice mutations not
invalidating a client's open-invoices key) and any existing Realtime subscriptions before proposing changes.

## Blockers

None. Part 3's code changes are uncommitted — confirm with Jafar before committing.

## Completion gate

Part 4: external changes update only affected tenant-safe caches.

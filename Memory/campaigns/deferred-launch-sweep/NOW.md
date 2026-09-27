# Now — Deferred launch sweep

**Goal:** Clear the ready deferred tasks before the first paying client, most urgent first.

**Active part:** 2 — Broken things (Opus). Part 1 done `32f49eb0`. Part 2 done so far: office inbox access
(`38af248e`, Jafar approved office = full team inbox), billing-reminder card (`2b8bf446`), tab-in-URL helper
`src/lib/url-param.svelte.ts` (`7e2686c5`).

**Exact next action:** `full-page-load-hydration-crash-leaves-the-previous-page-on-screen` (reproduce first),
then the rest of the Part 2 list in ROADMAP order. Fix, verify, delete each note and its deferred INDEX row,
commit per fix.

**Blockers:** None. Do not touch packages (Jafar, 2026-09-27).

**Pointers:**
- Memory/campaigns/deferred-launch-sweep/ROADMAP.md Part 2 (task-note names)
- Memory/deferred/<task>.md for each task

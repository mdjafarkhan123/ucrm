# Now — Deferred launch sweep

**Goal:** Clear the ready deferred tasks before the first paying client, most urgent first.

**Active part:** 2 — Broken things (Opus). Fixed so far: office inbox access, billing-reminder card, tab-in-URL
helper (`src/lib/url-param.svelte.ts`), formatting read for Settings-denied members, schedule-dialog banner,
review history wording. Also fixed the failing production build (`4a0e415f`). Hydration crash: investigated,
not reproducible, parked in its note.

**Exact next action:** `job-visit-override-pricing-photo-removal-not-trashed` — first answer the shared-file
check at the bottom of its note. Then `marketing-release-leftovers`, `staff-own-actions-lag-behind-realtime-echo`.
Fix, verify, delete each note and its deferred INDEX row, commit per fix. Then close Part 2 in ROADMAP.

**Blockers:** `team-seat-count-overshoots-right-after-an-invitation` needs Jafar's OK to send one real test
invite (to his own +alias); ask before touching it. Do not touch packages (Jafar, 2026-09-27).

**Pointers:**
- Memory/campaigns/deferred-launch-sweep/ROADMAP.md Part 2 (task-note names)
- Memory/deferred/<task>.md for each task

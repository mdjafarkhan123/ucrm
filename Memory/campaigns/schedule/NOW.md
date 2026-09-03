# Schedule: Current Checkpoint

- Goal: Deliver a desktop contractor dispatch desk without duplicating Job, Visit or other domain truth.
- State: Part 6a-2 (Schedule-owned Events) **COMPLETE** — build + type/test green + browser-verified
  2026-09-03 (create/edit/delete across Week/Day/Month, preview, seeded + no-date create, hard-delete
  confirm, validation all confirmed live; all test events deleted). This closes V1.1 (6a-1 + 6a-2).
- Branch `schedule-5b-visits-card`. **Work is uncommitted** (new EventCard/EventPreview/ScheduleEventDialog,
  /api/schedule/events route, schedule_events migration, plus the wired grids/page/api/schema).
- Count-label fix DONE 2026-09-03: day/row totals now count all kinds neutrally as "item(s)" via
  `itemCountLabel` in items.ts (Week/Day use it; Month keeps its split number/word spans). Verified live
  (Week headers read "1 item"); check 0 errors, 135 schedule tests pass, prettier clean.

## Next action

1. Commit Part 6a-2 (ask Jafar first — pattern is one commit per part, e.g. prior "Schedule 6a-1: ...").
2. Then select the next part. Only Part 7 (contextual Map + Anytime routing) is potentially dependency-ready,
   but it **needs Jafar's approval on the map/directions provider boundary** (Part 1b) before planning, plus
   dated geocoded Visits. Part 6b is Deferred; Part 8 is closure (needs 2–7). So Part 7 planning is the
   likely next campaign step once the provider decision is made.

## Boundary

- Jobs owns Visit/Job truth; Requests owns Assessment truth; Schedule owns Events (its first native write).
- Events land in the Day board's **Unassigned** row (no assignees) — accepted minimal rendering.
- Per-row RLS cost app-wide: Memory/deferred/app-wide-rls-helpers-run-once-per-returned-row.md.

Resume command: read memory and continue the Schedule campaign.

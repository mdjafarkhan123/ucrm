# Time clock Part 5 — live journey, 2026-10-12

Dev app (`localhost:5173`, managed Supabase), signed in as the contractor owner of Raad LTD (`Login.md`),
business clock Asia/Dhaka. Script: `journey.mjs` (`--width=1440`, `--width=390`). Screenshots are numbered by
step at each width.

| Step | What happened | Evidence |
| --- | --- | --- |
| 1–3 | **Add entry** for a team member on Sun Oct 11, Job #29, 8:00 AM – 12:00 PM, with notes; the dialog worked out 4h; the entry showed on their row | `2-add-filled`, `3-added` |
| 4–5 | **Edit**: start moved to 7:30 AM; the entry read 4h 30m and "Typed · Edited" | `4-edit-filled`, `5-edited` |
| 6 | **History**: "Added by you" (person, Job, time, 4h, notes), then "Changed by you" with Time 8:00 AM – 12:00 PM → 7:30 AM – 12:00 PM | `6-history` |
| 7–8 | **Delete** with confirmation; the entry left the row | `7-delete-confirm`, `8-deleted` |
| 9–10 | Manager **Clock in** from the person's menu; the running clock showed on their row | `9-person-menu`, `10-clocked-in` |
| 11 | **Running timer edit**: only Started on, Started at and Notes offered; start moved back 90 minutes | `11-running-edit` |
| 12–13 | **Clock out at a set time** 30 minutes ago: one General entry of 1h 1m recorded, nothing left running | `12-stop-at-set-time`, `13-clocked-out` |
| 14 | A field member (own time only) sees only themselves; no Clock in for others | `14-field-member-own-390` |

Database outcome (`time_entry_history`, Asia/Dhaka): added 08:00 / 240 min → changed 07:30 / 270 min → deleted;
running timer changed to start 07:27 → stopped with 61 minutes. Test entries were deleted afterwards through
the same route.

Screen check: round 1 at 390px found the start and end time fields cut off ("8:00 AN") and the delete
confirmation's two sentences run together. Both were fixed (time fields stack under 480px; a gap between the
sentences), and round 2 showed nothing more to fix.

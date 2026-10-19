# Shared parts — earlier approval details

Preserved from C5 when recording Batch 6b completion, 2026-10-19.

## Batch 5 redraw decisions (Jafar, 2026-10-19)

New behaviour approved: quick dates (Today, Tomorrow, Next week = next week-start day) above the month; end
times show their length from the start ("2 hr after start" chip). Declined: current local time in time-zone
rows; a 15-minute time list (Jafar: the live hour / minute-in-5s / AM-PM picker is more flexible — keep it,
improved look; Jafar picked the "indigo dial": hour : minute columns fading from a soft `color-time-surface` band, AM/PM segmented switch, green only on Done; A/C options deleted). Rule: per part, a new look or an improved live look, never a copy (design skill pref 9). Look: indigo
`color-time` tile at the front of date/time/time-zone boxes, weekday beside the date, raised green picked day,
today = bold date + green dot, slim quick-date pills (Jafar chose green over indigo), round flags, grey code/offset pills, typed letters in green.


## Batch 4 (approved 2026-10-19)

Board `j3jDI`; looks are in design modules `layout.md`, `cards.md`, `notices.md`. Build notes: the card tile's
live default `job` tone must become a per-caller tone; Banner has no close (live has none). Codex builds approved parts and Schedule on its own branch;
Claude draws, reviews and merges (Jafar 2026-10-19).


**Rollout rule (Jafar, 2026-10-19):** an approved built shared part applies at every call site. SegmentedControl, Checkbox and ClientPicker had their concept appearance gated by a page wrapper; restriction removed and verified live on New client and New job. Light/dark switch screenshots: `docs/evidence/2026-10-19-fields/client-switches-*.jpg`. Focused ESLint, Svelte compile and autofixer passed.

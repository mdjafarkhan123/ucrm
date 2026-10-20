# Time clock

> Dependencies: `colors.md`, `radius.md`, `buttons.md`, `cards.md`

The work timer on a visit or an assessment: the ticking time, the running clock, Start and Stop, the "running
elsewhere" line. Pencil: board "Time clock" (`ooCwt`), approved 2026-10-20. Timers use the Time family
(`--color-time`); over 12 hours they switch to `--color-warning`.

## Ticking time

- 700 weight, tabular figures, `h:mm:ss` ("1:24:07"). On its own it is 14 `--color-text`.

## Running clock

- Capsule 26 high, pill corners, padding 0 10 0 6, gap 6, `--color-time--surface`.
- Live dot: a 14 ring of `--color-time` at 25% with a 6 `--color-time` dot in its centre. The ring breathes
  (25% → 10%, dot 100% → 50%) over 1.6s; still when reduced motion is on.
- Time 12/700 `--color-time--onSurface`.
- Over 12 hours: the same in the warning family, then "Over 12 hours" 12/600.
- Used for other people's timers (Labor card "Running now" rows, at the row's right).

## Start and Stop

- Small secondary buttons (`buttons.md`): "Start timer" with a 16 `play`, "Stop timer" with a 16 `square`, both
  icons `--color-time` (`--color-warning` over 12 hours). Loading spinner in the same colour.

## Your timer panel

Visit pop-up and Job page, full width of its column (328 in the pop-up). Radius 8, padding 12, gap 12, items
centred: a 32 tile (`--color-time--surface`, 16 `timer` in `--color-time`), the text (gap 2), the button at the right.

| State | Panel | Text |
|---|---|---|
| Not started | `--color-surface--background--subtle`, 1px `--color-border` | "Your timer" 13/600 over "Not started on this visit" 12 quiet; Start timer |
| Running here | `--color-surface`, 1.5px `--color-time` | The time 20/700 (-0.3) heading over "Since 9:04 AM" 12 quiet; Stop timer |
| Over 12 hours | `--color-surface`, 1.5px `--color-warning`; tile in the warning family | The time 20/700 over "Over 12 hours" 12/600 `--color-warning--onSurface`; Stop timer |
| Running elsewhere | as Not started | "Running on" 13/600 heading, then "Job #1042" 13/600 `--color-interactive` with a 14 `arrow-up-right` (the link), over "Stop it there to start another." 12 quiet; no button |

## In today's visit row

The clock joined to Stop, both 32 high, side by side with no gap:
- Clock half: `--color-time--surface`, 1.5px `--color-time` edge, corners 8 0 0 8, padding 0 10 0 8, gap 6;
  live dot, then the time 13/700 `--color-time--onSurface`.
- Stop half: the small secondary "Stop timer" (indigo `square`), its normal `--color-border--interactive` edge
  on top, right and bottom, corners 0 8 8 0. Hover, pressed, focus and loading as `buttons.md`.
- Over 12 hours: the clock half in the warning family with "Over 12 hours" 12/600; the Stop icon turns
  `--color-warning`.

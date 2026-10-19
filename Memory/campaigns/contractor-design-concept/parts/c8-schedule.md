# Schedule — concept drawing

**Campaign:** contractor-design-concept · **Checklist row:** `stages/list-2a-daily.md` → `(app)/schedule`
**Branch/worktree:** `codex/concept-schedule`, `.worktrees/concept-schedule` · **Claim:** `e4d47ceb5e70`
**State (2026-10-19):** Week approved by Jafar, then the improved variant approved the same day. The final
drawing is `a7LTbd` "Concept · Schedule · Week · Owner · 1440"; the first version `JpHqG` was deleted. Its look is
written in the design skill: `calendar.md` (new), joined group in `buttons.md`, outlined pill in `badges.md`.
Next: Day view.

## Research

Jobber screenshots in `Design/schedule-visits-research/jobber/`. Jobber: Month / Week / Day, Anytime lane, Today
and arrows, Type / Team / Status filters, unscheduled count, Map, More; a visit opens a small pop-up. Our live
Schedule already behaves the same, so the drawing needs no new data except event completion (below).

## Week as drawn

Everything is in `.claude/skills/design/calendar.md`. Late follows `src/lib/schedule/status.ts`
(past day, not done). Events are drawn completable (below).

## Decisions (2026-10-19)

- Card colour = kind of work, not status (Jafar delegated; Jobber default, colour map "a record keeps its colour").
  Status always in words; no "In progress" look (the app only guesses it from the clock); no animation.
- Any completed card turns silver. Events can be completed (Jafar chose Jobber's way).
  **New behaviour for the build:** `completed_at` on events (migration), `/api/*` write with Zod, a tick in the
  event pop-up. The live app colours cards by status today; the build changes that.

## Next

1. One at a time: Day (people rows), Month, visit pop-up, Unscheduled drawer, Map.
2. Jafar saves Pencil (Ctrl+S); commit `concept.pen` from the main folder under this claim.

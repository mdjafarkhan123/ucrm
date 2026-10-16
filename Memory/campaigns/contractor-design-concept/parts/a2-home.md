# A2 — Home (App look)

**Branch/worktree:** `claude/a2-home`, `.worktrees/a2-home`. **Claim:** `49ac62f46feb`. **State:** Waiting to merge.

**Built (Pencil `jI9aE`):** Owner Home with greeting and clock card, setup card, To-do board (Requests, Quotes, Jobs, Invoices), dark Today schedule card with By visit / By person, Money owed card with ageing bar and most-overdue list, Business performance card. New parts in `components/dashboard/` (HomeTodoCard, HomeScheduleCard, HomeMoneyOwedCard, HomePerformanceCard, HomeCardState, FieldWorkerHome) and helpers in `src/lib/home/` with `home.spec.ts`. No new API routes.

**Checked:** 1440 light and dark as owner, 1440 light as field worker (same content as before, new look). Type check, lint and tests NOT run (lead runs once for the batch); `home.spec.ts` not run.

**Leftovers:** Schedule card turns light in dark mode (Jafar chose to keep money/feature cards light in dark mode, 2026-10-16). Not checked at 1100.

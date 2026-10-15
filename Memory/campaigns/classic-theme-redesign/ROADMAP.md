# Classic theme redesign — roadmap

**Plan:** `docs/classic-theme-redesign-behavior-contract.md`. First delivery approved 2026-10-13;
whole-application goal, new-concept priority and design → build → live check → synchronize → clean loop
approved by Jafar 2026-10-15. Approval covers the stage order below. New screen designs still need his yes.
Jafar clarified on 2026-10-15 that this campaign designs the desktop web app; the separate phone app is later work.

| Part | Plan section | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- | --- |
| 1 Plan: scope and direction | § First version; § Direction agreed so far | Scope, font, platform, card-shell and addition answers | — | First-version questions answered and Jafar approves the scope | Done 2026-10-13 — Jafar approved |
| 2 Design: new look and design system | § Design target | Claude concept chosen as Classic; design review; rebuilt Classic design-system page with light and dark tokens and parts — in `classic.pen` | 1 | Jafar approves the reviewed reference screens and design-system page | Done 2026-10-13 — approved; `classic.pen` committed `41d154c6` |
| 2B Design: record pages in the new look | § Design principles; recipe § Record page structure | Job, quote and invoice redrawn in the new look; request, payment and client pages designed — desktop, in `classic.pen` | 2 | Jafar says yes to the named screens; date and names recorded in the plan | Done 2026-10-13 — all six approved; first concepts deleted |
| 3 Build planning | § Shared building blocks; § Technical boundaries | Build parts per shared block and page, using the CRM design system's theme foundation so Classic changes leave Botanical untouched; Text button settled | 2B | Parts with checks and order approved by Jafar | Done 2026-10-13 — Jafar approved ("all agreed") |
| 4 Whole-app inventory | § Later stages | Assign every remaining Business Workspace, Control Room, sign-in and customer-facing route to a focused screen part before its stage starts | H stage | No live route is missing; each part has a design, build and live done-check | Planned |

Stage order: [B1–B4 and six record pages](stages/first-version-build.md), with
[B3b remaining shared parts](stages/shared-parts.md) between B4 and B5; then
[lists, Schedule, Settings, Home/Reports and the rest of the app](stages/whole-app.md).
The record/list/Schedule Pencil approvals are linked from `NOW.md` and their part notes. Later screens are
designed and approved as their stage approaches; concept-only work should not outrun implementation.

# Page parts — batch 4 branch build

**Stage:** Merged 2026-10-19 at Jafar’s explicit request.
**Branch/worktree/claim:** `codex/approved-shared-schedule-build` · `/home/jafar/.codex/worktrees/approved-shared-build/Ucrm` · `fff612924b43` (release after successful push).
**Approval:** Jafar 2026-10-19; board `j3jDI`, breadcrumb option C. Claude designs/reviews/merges. Pencil and design skills stayed read-only.

## Built

- PageContainer: existing non-card pages keep the approved single white card (16 radius and border); open pages stay on the warm background. Full width follows the browser (Jafar’s later clarification); narrow 640; two-panel uses a 360 rail.
- SectionBlock: standalone cards use CardHeader everywhere, without the Job-details context gate. Form groups retain fieldset/legend semantics, with the approved top rule and 16px title. Body 20 padding and 16 gap; flush rows retain their own spacing.
- RailCard: shared compact CardHeader, no shadow, 16 body spacing. Counts move to the hint. Subject tone is explicit at existing callers; Billing/invoice reminders are invoice blue, Notes conversation teal, files neutral, record/section cards their own family. Kept existing children direct so caller selectors continue to work.
- Breadcrumbs: capsule, back circle, chevrons, current-page semantics, hover/focus; preserved caller-resolved navigation. Optional item icon; existing items remain compatible.
- Banner: 16 radius, 32 surface tile/16 meaning icon, tinted strip and 14/500 message, existing optional action and status/alert semantics. No close button added.
- Fixed the attachment empty-state padding exposed by flush rail headers. No behavior, permissions, writes, dependencies or schema changed.

## Evidence

`docs/evidence/2026-10-19-page-parts/`: real form-builder breadcrumb/fallback card light/dark; real Job #30 section/rail light/dark; Instructions edit opens and cancels correctly; all four Banner tones, section/card/form-group and base statuses checked together at 1440 and 390 light/dark. Narrow page scrollWidth equals viewport width. Keyboard breadcrumb focus checked. Temporary visual preview removed after screenshots; synthetic notice actions were not exercised as real mutations.

Five shared parts plus Card and the attachment spacing fix compile without warnings. Svelte MCP autofixer passes after SCSS preprocessing. No full typecheck, lint suite or test suite run, per Jafar’s instruction to defer long checks. Caller edits assign subject tones; no business logic changed.

Compared with read-only Pencil sections `CZ4hr`, `n9pWZJ`, `U8Ftlb`, `Y4vLy`. Built ticks now describe integrated main. Pencil drawing cleanup remains with Claude.

## Next

Continue the next approved shared-parts batch. Schedule is also integrated; see `docs/evidence/2026-10-19-schedule/README.md`.

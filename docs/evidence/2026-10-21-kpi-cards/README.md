# Approved KPI cards — 2026-10-21

Reference: `concept.pen` board `fzPaM`, Approved B. Implementation uses one KpiCard for status cards,
report cards and the green list summary. No new queries or writes.

## Browser proof

The running branch app used the existing Raad LTD owner session and real remote data. Clients (4),
Requests (6), Jobs (6), Quotes (5), Invoices (5) and Reviews (4) checked at 1440 and 390 in light and dark.
Screenshots are named `<page>-<width>-<theme>.jpg`. All checked cards stayed inside their width; their
rows matched heights. Jobs at 900 wraps 3+3; at 390 wraps 2+2+2. Reviews keeps its existing page frame.
Money/conversion cards retain their previous supporting figures, so their contents can make a row taller
than the example board. The final layout change affects long values on narrow cards only.

`jobs-selected-dark.jpg`: picking Late sets both the selected card and Status: Late.
`jobs-keyboard-focus-dark.jpg`: Space clears that filter; the keyboard focus ring stays visible.
`states-390-dark.jpg`, `states-390-light.jpg`, `states-1440-light.jpg`: temporary component fixture covering
loading, zero counts, failure wording, no price access, long labels/figures, and disabled controls. The fixture
was removed. Long amounts now stack below their tile and use a smaller readable number on narrow cards.
No real records were created, modified, sent or deleted. Price access rules and query ownership are unchanged.
Existing KpiCard consumers were inspected in code; their compatible props are retained. No admin-role
browser tour or broad campaign checks were run.

## Focused checks already completed

- SCSS-preprocessed Svelte compiler: all 8 changed Svelte files, zero warnings.
- Svelte MCP after preprocessing: both shared components clean. Page diagnostics refer to existing
  resolved-path helpers and debounce/timer effects; those are unchanged.
- Focused svelte-check (8 files, generated ambient declarations included): 0 errors, 0 warnings.
- Existing client overview, quote overview and invoice facts tests: 3 files, 22 tests passed.
- Focused ESLint: 0 errors with type service disabled (types checked separately) and the navigation rule
  disabled because it cannot follow the existing resolved-path helpers. One existing unused-disable warning
  remains on Reviews because its navigation rule was disabled for this run.
- Prettier on changed Svelte files; git diff whitespace check clean.

At Jafar's 2026-10-21 instruction, further long checks are deferred to campaign closing.

## Integrated live proof

2026-10-21: Jafar authorised integration while preserving Claude's design files. Merged into main,
then opened `https://app.upliftcontractor.com/jobs` in the integrated browser: six KPI cards with real
owner data. Screenshot: `main-jobs-live.jpg`. The pre/post merge hashes of `concept.pen` and the unsaved
`design/guide.md` match. New Money summary card design guidance from main was retained. No further
long checks were run after Jafar's instruction.

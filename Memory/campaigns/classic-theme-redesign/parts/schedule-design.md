# Schedule — design

**Campaign:** classic-theme-redesign · **Plan:** `docs/classic-theme-redesign-behavior-contract.md` § Later stages
**Stage:** Design · **Follows:** the five approved lists ([Requests, Quotes and Invoices](requests-quotes-invoices-lists.md)).
**Code:** `classic.pen` in the main folder; commit it from main in its own commit after Jafar presses Ctrl+S in
Pencil. These notes live on branch `claude/schedule-design` (worktree `.worktrees/schedule-design`).
**Done when:** Jafar approves `Schedule · 1440` and his answers are written here.

## Steps

- [x] Jafar, 2026-10-14, chose Schedule as this session's screen; a subagent researches and draws, the parent
      session reviews.
- [x] Research: Jafar's saved screenshots (`Design/schedule-visits-research/`, `Design/Jobber Jobs/2026-08-31/`
      62–70, `schedule1.webp`), Jobber, Housecall Pro and ServiceTitan help pages, and
      `docs/schedule-behavior-contract.md` (Week is the default view).
- [x] `Schedule · 1440` (`RrFyy`, x 10780, y 4080) drawn, light and dark checked. Parent review fixed a
      clipped "Unassigned", per-person avatar colours (now one neutral style), the 7am label and long titles on
      narrow cards.
- [ ] Approved by Jafar. Questions put to him: Week or Day as the default view; the proposals below.

## Proposals (not in the app today; data exists)

- Card edge colour by kind (visit green, assessment amber, event grey, Late red); team shown by neutral initials,
  replacing today's per-person `schedule_color` edges.
- Green "New job" button in the page header, opening today's quick-create (Job / Request / Event).
- Legend row under the calendar.
- Sidebar collapsed on Schedule so seven columns stay readable.
- If neutral team initials are approved, `Job details · 1440` still uses per-person tints; ask whether to match.

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
- [x] Jafar, 2026-10-14: asked for more variants and said the visit cards did not look premium; colour should
      mean something. Three variants drawn beside the original (row y 4080), light and dark checked:
  - `Schedule · 1440 · A · Colour shows status` (`QOFVk`, x 12340) — recommended. Scheduled = white card,
    In progress = the one dark-green featured card, Late = rose tint, Unassigned = amber tint with Assign,
    Completed = soft grey with green tick; Assessment and Event shown by icon. New legend.
  - `Schedule · 1440 · B · Colour shows who` (`PmCvg`, x 13900) — Jobber/Housecall Pro way: each crew member
    a tint (Daniel blue, Sofia violet, Amir teal, Maya amber); shared/unassigned stay white; legend lists people.
  - `Schedule · 1440 · C · Day by team` (`JMYsG`, x 15460) — Day view, one column per crew member with booked
    hours bar, A's status colours, live progress on the in-progress visit.
- [x] Jafar, 2026-10-15: deleted C. Card colour shows status (his idea, confirmed against dispatch-board
      practice); he likes A's soft red Late card and that each status badge has its own colour.
- [x] A improved 2026-10-15 (Jafar: improve A first; keep B for now, delete later): amber "Unassigned" badge
      replaces the Assign button (assigning happens from the preview); day headers add a coloured attention
      count ("1 late", "1 unassigned"); the open card gets a rose selection ring; long Anytime names end "…".
- [x] Jafar, 2026-10-15, asked why In progress is deep green. Review board `Schedule · Status colours review`
      (`Dp8ki`, x 12340, y 5252) compares A's solid dark-green card with the suggestion: white card, green
      outline, green "In progress" badge (ServiceTitan: Working = green, Done = light grey; Housecall Pro: in
      progress = white tile with outline; Jobber: completed greyed with a tick). Waiting for his choice.
- [ ] Approved by Jafar. Questions put to him: which card colour (A status / B person / original type bar);
      Week or Day (C) as the default view; the proposals below.

## Proposals (not in the app today; data exists)

- Card edge colour by kind (visit green, assessment amber, event grey, Late red); team shown by neutral initials,
  replacing today's per-person `schedule_color` edges.
- Green "New job" button in the page header, opening today's quick-create (Job / Request / Event).
- Legend row under the calendar.
- Sidebar collapsed on Schedule so seven columns stay readable.
- If neutral team initials are approved, `Job details · 1440` still uses per-person tints; ask whether to match.

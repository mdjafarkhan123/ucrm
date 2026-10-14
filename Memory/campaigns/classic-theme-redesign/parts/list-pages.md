# List pages — design

**Campaign:** classic-theme-redesign · **Plan:** `docs/classic-theme-redesign-behavior-contract.md` § Later stages
**Stage:** Design
**Code:** `classic.pen` in the main folder (Pencil saves there); commit it from main in its own commit, under a
claim covering `classic-pen-list-pages`.
**Done when:** the shared list layout is approved in Pencil and its build part is placed in the roadmap.
**Read next:** the design recipe (`docs/classic-theme-redesign-design-recipe.md`); `Jobs · 1440` in `classic.pen`.

## Order change

Jafar, 2026-10-14: list pages are designed before the later-stage planning (roadmap Part 4, which waited for B12),
starting with Jobs — "all listing page use the same component", so one approved list sets the look for Jobs,
Quotes, Invoices, Requests and, mostly, Clients. All of them share `PageHeader`, `StatusOverviewCard`, `KpiCard`,
`FilterBar`, `DataTable`, `ListLoadMore` and the empty, error and loading states.

## Steps

- [x] Research: Jobber's Jobs list (overview counts, Status and Type filters, table, "Filtered jobs" heading) and
      Housecall Pro's inline filters; the real page `src/routes/(app)/jobs/+page.svelte`.
- [x] `Jobs · 1440` (`uqJjO`, x 3080, y 4338) drawn in light, dark checked. **Approved by Jafar 2026-10-14**
      ("approved"), including the three proposals it shows:
  - The five overview counts (Late, Unscheduled, Action required, Requires invoicing, Ending soon) become
    tiles that filter the table when pressed; today they are counts only. Late has the rose tile.
  - Search and the Status, Type and Created filters sit in the table card's header, always visible, instead of
    behind a Filters button.
  - Job type moves from its own column into the job's second line (`#1058 · Recurring`).
  - Also in the layout: visits today and completed visits in the card's foot strip; collected this month and
    left to collect in the dark featured card; client initials all in client violet.
- [ ] "More actions" stays as today (disabled with its reason) until something sits behind it — Jafar was asked
      whether to hide it instead and has not answered; ask at build planning.
- [ ] Next list screen in a new session, one per session, if Jafar wants the others drawn; otherwise plan the
      shared list build part from `Jobs · 1440`.

## Notes

- No total count on the list: paging is keyset (`next_cursor`), so the foot shows only "Load more jobs".
- A role without invoice price access sees dashes and "Needs invoice price access" in the money card, as today.
- Not drawn: the empty, filtered-empty, loading and error states — build them from the existing components.
- `NOW.md` and `ROADMAP.md` gain a pointer to this note when the B3 session releases the campaign notes.

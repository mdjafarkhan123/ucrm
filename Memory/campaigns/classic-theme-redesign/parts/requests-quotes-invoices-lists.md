# Requests, Quotes and Invoices lists — design

**Campaign:** classic-theme-redesign · **Plan:** `docs/classic-theme-redesign-behavior-contract.md` § Later stages
**Stage:** Design · **Follows:** [Clients list](clients-list.md) and `parts/list-pages.md` on branch
`claude/jobs-list-design` (Jobs list approved 2026-10-14).
**Code:** `classic.pen` in the main folder; commit it from main in its own commit after Jafar presses Ctrl+S in
Pencil. These notes live on branch `claude/list-pages-rqi` (worktree `.worktrees/list-pages-rqi`).
**Done when:** Jafar approves `Requests · 1440`, `Quotes · 1440` and `Invoices · 1440` and the answers are
written here.

## Steps

- [x] Jafar, 2026-10-14: draw several screens in one session with subagents, the parent session reviewing
      ("you stay as reviewer? let subagent work?").
- [x] Drawn from `Jobs · 1440`, light and dark checked: `Requests · 1440` (`j1lupj`, x 6160, y 4080),
      `Quotes · 1440` (`uEjrw`, x 7700), `Invoices · 1440` (`t3A3mj`, x 9240).
- [x] Parent review: Quotes tiles changed to the Invoices tile anatomy (label, count, bold amount + words);
      Requests' conversion bar moved under the divider, as on Invoices.
- [ ] Show Jafar; record his answer and each proposal's outcome here.

## Proposals waiting for Jafar (not in the app today; data checked by the drawing sessions)

All three: overview tiles filter the table when pressed (as approved on Jobs).

- **Requests:** "Waiting 25 min" amber line on New and Needs approval rows (`requested_at`); Assessment column
  with booked time and who is going, or the customer's asked-for time (`preferred_time`, `assessment_assignees`
  — not yet in list data); "↳ Quote #318" on converted rows; Created filter; phone under the client name;
  conversion dark card (26 new, 16 turned into a quote or job); tile named "Ready to quote" while the pill keeps
  "Assessment complete" (the longer name does not fit the tile).
- **Quotes:** money on each tile and a bar of where open money sits (`quote_versions.total_minor`); foot strip
  "waiting more than 7 days", "sent but not opened" (`quote_access_links.view_count`) and follow-up emails
  setting; a follow-up line under each status (opened 2×, approved online, became Job #1042); conversion
  card replacing today's empty KPI cards.
- **Invoices:** money on tiles (Draft total is a new sum); "12 days on average to get paid"; "Overdue reminders
  on"; due-date notes ("7 days late", "In 14 days"); row notes "Viewed 3 times", "Not opened yet", "Part paid";
  dark "Owed to you" card split into Overdue and Not due yet.

## Questions for Jafar

1. Invoices "Awaiting payment" pill: amber (drawn; colour rule says amber = waiting) or blue as the app today.
2. Quotes follow-up strip when the automation is off: show a "Turn on follow-up emails" link (suggested).
3. Quotes: keep the Created column (drawn; the list sorts by it today) or show Sent.

## Notes

- Requests have no number and website requests have no saved source, so neither shows.
- Not drawn: empty, filtered-empty, loading, error and no-price-access states — build from existing parts.
- Pencil's `problems` check reports false "clipped" warnings on these frames; full-size exports show none.

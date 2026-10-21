# Batch 50 — Job billing pop-ups, proof (2026-10-21)

Live app from branch `claude/job-billing-popups-build` (dev server on port 5208), Chrome, 1440 wide, Raad LTD owner
login, light and dark. Compared with Pencil `aJGHA`: Billing setup B `u4Bwht`, Payment schedule B `vBA3r`, Add an
invoice reminder A `z8Yp8f`, dark frames `zAaIh`, `IqvDd`, `uQJDt`. Test job #30 (one-off, $2,160.00) and #29
(recurring, $250.00 a billing period).

| Shot | What it shows |
|---|---|
| `billing-recurring-light.jpg`, `billing-recurring-dark.jpg` | Billing setup on a repeating job: price box open, read-back strip, three-decisions panel (Price, Invoice reminder, Collect the money greyed with "Not set here"), Save billing off until something changes |
| `schedule-first-light.jpg`, `schedule-first-dark.jpg` | Add a payment schedule, first time: two blank stages, "Job total" panel with an empty bar, all of the total left to assign |
| `schedule-doesnt-add-up-light.jpg` | $1,000 + $700 against $2,160: notice strip at the top of the stages, bar and legend update, $460.00 left to assign in warning colour |
| `schedule-percentages-light.jpg` | Percentages mode 40% / 60%: percent box with `%`, each stage's amount at the right, $0.00 left to assign in success colour |
| `reminder-light.jpg`, `reminder-dark.jpg` | Add an invoice reminder: date, note, informative strip; Add reminder off until a day is picked |

Main journeys pressed on the live app (test job #30, then put back):
- Billing setup: picked "Never remind us — we will decide", the panel read it back, Save billing saved it and the
  card showed it; saved the original choice back.
- Payment schedule: saved a 40% / 60% schedule, both stages showed "Still to bill" with Create invoice, reopened as
  Edit payment schedule with Remove schedule at the left, removed it.
- Reminder: added Nov 30, 2026 with a note, it appeared in the card, deleted it.

Not pressed: the stage-already-invoiced look (needs an invoice on a stage), couldn't-save from the server, and the
view without money access; those share the same notice strip and disabled looks as the states above, and the save
logic is unchanged.

Differences from the drawings: the date box keeps the live date field (month, day, year segments and the calendar)
instead of the drawing's text box, as on Collect payment. Icons use Tabler names (`coin`, `list-numbers`,
`stack-2`, `cash-banknote`, `percentage`, `trash`, `alert-triangle`).

# Jobs: Current Checkpoint

- Goal: Research Jobber Jobs deeply, then build simpler contractor workflows without losing useful features.
- Contract: `docs/jobs-behavior-contract.md`. Parts 1-10 committed (`5737804`); 11a committed (`85df29d`);
  11b committed (`1ae6042`).

## 11b closed
Invoice reminders + Requires invoicing shipped and browser-verified: add reminder, mark invoiced, delete,
status flip to "Requires invoicing", list filter chip. Fixed a shared `CalendarPicker.svelte` bug along the
way (each date segment was keyed on its own value, so typing destroyed/recreated the focused DOM node after
one digit) — this affects every screen using the component, not just this dialog.

## Next: pick between 11c and Part 12
- **11c** (payment installments + per-visit amounts) is blocked — its roadmap dependency "Invoice boundary"
  has no approved contract yet (no `docs/invoice-behavior-contract.md`).
- **Part 12** (integrate Jobs/Visits into the unified Schedule) has its dependencies met (Parts 9-10 done)
  but needs the Schedule foundation, which hasn't been scoped in this campaign.
- Ask Jafar which to pursue, or whether to scope the Invoice boundary first.

Resume command: `read memory and continue` (Jobs campaign).

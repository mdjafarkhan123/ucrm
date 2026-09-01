# Jobs: Current Checkpoint

- Goal: Research Jobber Jobs deeply, then build simpler contractor workflows without losing useful features.
- Contract: `docs/jobs-behavior-contract.md`, approved 2026-09-01.
- Parts 1-10 committed 2026-09-01 (`5737804`). Part 11a checked by Jafar and committed (`85df29d`).
- Jafar approved splitting Part 11 into 11a / 11b / 11c on 2026-09-01, and approved keeping New Job simple
  (one "invoice on close" checkbox) with the real billing setup on the Job detail page.

## Exact next action (resume here)
Start Part 11b: invoice reminders and the Requires invoicing derived status. Nothing is designed yet —
propose the reminder rules (after each visit, once on completion, monthly on the last day, custom date,
following Jobber) and the table/command shape to Jafar before building. See ROADMAP.md for 11b's gate; the
contract's "Billing timing and collection, kept separate" section is the authority on what a reminder means.

## Known deferred items (Jafar said "later", not oversights)
- Map duplicate job_number (Postgres 23505) to a field error instead of a 500.
- Make the New Job "Job #" field editable with a live duplicate warning.
- As-needed → recurring conversion; customised-visit preservation on regeneration; visit collisions; seasonal
  pause — all in the contract's deferred-decisions list.
- Whether a **closed** job may still be re-priced is unanswered and left to Part 13, which owns closing. The
  11a commands deliberately carry no closed-job guard, so today they would allow it.

Resume command: `read memory and continue` (Jobs campaign).

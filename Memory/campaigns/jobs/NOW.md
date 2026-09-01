# Jobs: Current Checkpoint

- Goal: Research Jobber Jobs deeply, then build simpler contractor workflows without losing useful features.
- Contract: `docs/jobs-behavior-contract.md`, approved 2026-09-01.
- Parts 1-10 CLOSED and COMMITTED 2026-09-01 (commit `5737804`).
- Jafar approved splitting Part 11 into 11a / 11b / 11c on 2026-09-01, and approved keeping New Job simple
  (one "invoice on close" checkbox) with the real billing setup on the Job detail page.

## Exact next action (resume here)
11a is code-complete and unverified in a browser. Ask Jafar to look at a Job detail page — editable scope
block, and the Billing / Discount / Tax cards in the right rail — then close 11a and start 11b
(invoice reminders + Requires invoicing). 11a is not committed yet.

## Known deferred items (Jafar said "later", not oversights)
- Map duplicate job_number (Postgres 23505) to a field error instead of a 500.
- Make the New Job "Job #" field editable with a live duplicate warning.
- As-needed → recurring conversion; customised-visit preservation on regeneration; visit collisions; seasonal
  pause — all in the contract's deferred-decisions list.
- Whether a **closed** job may still be re-priced is unanswered and left to Part 13, which owns closing. The
  11a commands deliberately carry no closed-job guard, so today they would allow it.

Resume command: `read memory and continue` (Jobs campaign).

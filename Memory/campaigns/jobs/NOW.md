# Jobs: Current Checkpoint

- Goal: Build simpler contractor Jobs and Visits without losing proven Jobber behavior.
- State: Part 13a CLOSED 2026-09-03 — tests written and passing (16/16,
  `src/routes/api/jobs/jobs-lifecycle.spec.ts`), `npm run check` 0 errors, and live browser walkthrough
  passed: complete → final-visit dialog → Finish job → on-completion reminder fired → Reopen job → visit
  actions restored → Mark Incomplete. Parts 1–11b, 13a complete.
- Contract: `docs/jobs-behavior-contract.md`.

## Next action

Awaiting Jafar's pick of the next thread. Candidates, none started:

- Part 11c (Payment installments and per-visit amounts) — blocked on the Invoice boundary.
- Part 13b (Invoice handoff) — blocked on 11c and the Invoice boundary.
- Part 14 (labor, expenses, Job costing) — dependency-ready (Part 8 done); Team/expense ownership scope
  unconfirmed.
- Part 15 (notes, attachments/photos, checklists, signatures) — dependency-ready (Parts 8–10 done); needs
  attachment storage decision.

## Deliberately deferred, not silently dropped

- The standalone "Close Job" button with the full incomplete-visits-removal preview (cancel a job that still
  has open work) — `close_job` only closes a job already at zero incomplete visits and refuses otherwise.
- Wiring Upcoming/Today/Late/Action required into `private.job_derived_status` / `job_list_rows` /
  `job_status_count_rows` — a separate, larger read-model change the Jobs list still needs. Both notes are
  recorded in the migration file's header comment too.

Resume command: `read memory and continue the Jobs campaign` (Jafar must pick the next part first).

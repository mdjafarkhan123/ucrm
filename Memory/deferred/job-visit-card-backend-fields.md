# Job Visits card — two backend fields the UI can't source yet

Deferred from Schedule Part 5b (Job detail Visits card parity, 2026-09-03). The card redesign shipped the 10
pure-UI items; these two contract items need Jobs-owned backend work and were deferred with Jafar's approval.

Reactivates when: Jafar picks up Job-visit history/series polish, or the Invoice boundary work touches the
visit read model anyway.

1. **Completed-by name.** The contract asks the card to keep completed-by/completed-at history. The
   `job_visits` table already stores `completed_by uuid`, but the job-detail read model (`JobVisit` in
   `src/lib/jobs/api.ts`, and the RPC/select behind it) never returns it, so the card shows the completed
   date only. Work: expose `completed_by` through the read model and resolve it to a display name (join to the
   team/member record). Small — no schema migration, but it is a Jobs server + type change, not UI-only.

2. **Off-series marker.** The contract asks the card to mark a Visit that differs from its recurring series.
   There is no column or read-model flag recording that a visit deviates from the rule, and Jobs — not
   Schedule — owns Visit truth, so it must not be guessed client-side. Work: a real Jobs decision + a stored
   deviation flag (or a server-side comparison against the series rule), then surface it as a row badge.

The card's [[schedule campaign]] Part 5 gate is otherwise passed; see
docs/schedule-behavior-contract.md "Job detail Visits card".

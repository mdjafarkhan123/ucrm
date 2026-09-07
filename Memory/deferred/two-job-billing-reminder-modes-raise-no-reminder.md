# Two job billing-reminder modes never raise a reminder

Found during Invoices campaign browser passes; carried out on completion 2026-09-07. Belongs to Jobs.

`On dates we pick ourselves` and `Once, when the job is finished` raise no billing reminder until a date
exists or the job closes. Both are selectable now, so a contractor can pick one and silently get nothing.

**Reactivates when** Jobs reminder work is next opened, or a contractor reports a job that never appeared
in Ready to bill.

Already known: the other modes (per visit, per period) do raise correctly, so this is the two missing
branches, not the reminder engine.

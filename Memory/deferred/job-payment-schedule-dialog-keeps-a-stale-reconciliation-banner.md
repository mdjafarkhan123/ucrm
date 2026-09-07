# The payment-schedule dialog keeps its refusal banner after the numbers are fixed

Carried out of the Invoices campaign on completion 2026-09-07. Jafar has seen it and not asked for a fix.

`JobPaymentScheduleDialog` shows a red "the stages must add up" banner on a refused save and keeps it until
the next save, even once the stages reconcile. The live "Adds up to X of Y" line underneath is correct
throughout, so the screen contradicts itself for as long as the banner stands.

**Reactivates when** that dialog is next opened for other work, or a contractor reports it.

Already known: the banner is the `error` string, cleared only in `write()`. The fix is to clear it when the
draft changes — small, but it is a behaviour change Jafar has not asked for.

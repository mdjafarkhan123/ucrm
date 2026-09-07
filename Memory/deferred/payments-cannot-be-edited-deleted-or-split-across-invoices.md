# A recorded payment cannot be edited, deleted, or split across invoices

Deferred through the Invoices campaign; carried out of it 2026-09-07 on completion.

Manual payment recording ships and is verified. Three gaps remain: a payment cannot be edited, cannot be
deleted, and one payment cannot settle several invoices at once. Today a mistyped payment can only be
answered by a reversal.

**Reactivates when** a contractor reports a mis-keyed payment, or the first customer pays several invoices
with one transfer.

Already known: the ledger is append-only by design, so edit and delete must be modelled as corrections
rather than mutations — the same shape the invoice-correction deferral needs. Consider them together.

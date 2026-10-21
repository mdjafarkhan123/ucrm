# New job page build — 2026-10-21

Built from Pencil `q6Ffc` "Batch 32 · New job page · Approved A" (light `RXUCw`, dark `z2sHH`).

## What changed

- `work/CreateFormHeader.svelte` — the shared create form (`OjBZG`): coloured top with the page title and the
  Title field; client picker on the left, the read-only record fact tile on the right. Built for Request, Quote,
  Job and Invoice; only New job uses it so far.
- `layout/RecordFormLayout.svelte` — concept `pageHeader={false}` + `labelledBy`, so the shared form carries the
  page title.
- `jobs/JobForm.svelte` — shared form on top; sections in Jobber's order Visits → Billing → Products.
- `jobs/JobVisitsBlock.svelte` — open visit edged in the time colour; who is going by name in its head;
  Anytime and Schedule later side by side.
- `quotes/ProductsAndServicesBlock.svelte` — `totalFoot`: the job subtotal as a full-width foot.
- Job total rail card unchanged (being redesigned in another session).

## Checked on the live app (Chrome, 1440, owner of Raad LTD)

- Light page compared beside `RXUCw`; dark page beside `z2sHH`.
- Picking two team members shows "Jafar Khan, Field Tester" in the visit head.
- Main journey: title, client "Jafar Test", one price-book line ($175.00), Notify customer off → Save job showed
  loading, then opened Job #31 with $175.00.

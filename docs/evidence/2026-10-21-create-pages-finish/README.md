# Create pages finished — New request, New invoice, money card (2026-10-21)

Approved designs: shared create form `NhVGQ` / `OjBZG` (Batch 31's replacement), New request `el2At`, Batch 36
New invoice A `C75AJ` / `kLaPi`, Batch 35 money summary card B `vIjf0` (New job `UHIua`).

## What changed

- `requests/RequestForm`, `invoices/InvoiceForm`: moved onto `CreateFormHeader` in the concept frame (separate
  cards, floating save bar with status line). `work/PrimaryInfoCard` deleted (no users left).
- `requests/AssessmentBlock`: draft state uses the Time colour and a slim "No visit booked" row.
- `work/DraftMoneyCard` (new): the Batch 35 card before save on New job, New quote and New invoice. Replaces the
  Job total card on New job and the plain draft card on New quote. `MoneyFeatureCard` gained pill tones
  (margin / below target / losing money) and icons on foot rows.
- `GET /api/records/money-access`: may this person see cost (`jobs.view_cost`, `quotes.view_cost`), and the
  target margin (read through RLS).
- New invoice: due date worked out from the picked term and shown read-only; chip "Due in N days" on the card.

## Screen check (dev server on this branch, Chrome, 1440 width, owner)

- New invoice empty and from job #30 (light and dark): matches `C75AJ` / `kLaPi`; whole-job bill shows
  "This invoice · whole job"; Net 15 → Nov 5, 2026 and "Due in 15 days".
- New request: matches `el2At`.
- New quote with a price-book line: $19 profit, 54% margin, cost $16 — matches the Batch 35 quote card.
- New job empty: matches `UHIua`.
- Nothing was saved; the save paths are unchanged.

## Checks

Pages compiled in the dev server with no new warnings. Full type check, lint and test suites deferred to campaign
close (Jafar, 2026-10-21).

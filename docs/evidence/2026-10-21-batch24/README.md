# Batch 24 — Discount, tax and totals (built 2026-10-21)

Pencil: `concept.pen` → `qY4yb` (approved A). Checked at 1440 on the branch's dev server, owner of Raad LTD.

| Screenshot | What it shows |
| --- | --- |
| `quote-card-light.png`, `quote-card-dark.png` | Quote #47 rail: Discount row with amount, Tax row with source line and amount, pencils |
| `invoice-card-light.png`, `invoice-card-dark.png` | Invoice #1 rail: same card in invoice blue |
| `newquote-card-light.png` | New quote: None added (quiet), Not configured (yellow tile and value); tax pencil waits for a property, as before |
| `discount-dialog-*.png` | 440 pop-up: quote tile, record line, Percentage/Amount with icons, quiet red Remove, Save with check |
| `tax-dialog-light.png`, `tax-custom-*.png` | 400 pop-up: Tax select, custom name + Rate % on one row, reusable checkbox, info note strip |

Main journey: opened Edit discount on Quote #47 and pressed Save discount — button busy while saving, pop-up
closed after 861 ms, "Discount saved" shown, card unchanged (same values re-saved).

`QuoteSummaryCard` had no users (the Batch 35 money card replaced it on create pages) and was deleted.
Not run, by Jafar's rule: type check and lint (once at campaign end).

# A2 Invoice details (a2-invoice-details)

Branch `claude/a2-invoice-details`. Pencil frame `u9I5Gw` "Invoice details · App look · 1440".

## Built
- `invoices/[id=uuid]/+page.svelte` on the App look (`PageContainer open`, `RecordDetailLayout cards`): header with status, "Invoice #N", history button, Collect payment (card icon), client row, facts strip (invoice date, due with term, sent/issued, viewed) plus a pencil that opens the existing terms editor; Products and services card with the quiet line and the totals (subtotal, discount, tax, invoice total) inside it; History card (Payments / Edits tabs); Contract disclaimer card; rail with dark Balance card, Online payment, Discount and tax, Photos and files.
- Save bar behaviour unchanged (title, terms, disclaimer stage and save together). The Terms form now shows only while editing.
- New parts: `invoices/InvoiceHistoryCard`, `work/RecordAdjustmentRow`.
- Extended shared parts (all opt-in): `MoneyFeatureCard` (badge, pill, percent, extra rows, inset, `record`), `RailCard` (`description`, `flush`), `Tabs` (`compact`, per-tab `badge`), `ProductsAndServicesBlock` (`hint`, `totalRows`), `RecordDiscountCard`/`RecordTaxCard` (`embedded`), `WorkRecordHeader` (primary action `icon`, 40px primary in the App look), `SectionBlock` (bordered pencil, tight subtitle).

## Evidence
Live screenshots at 1440 and 1100, light and dark, for paid, past due with deposit credit, draft, voided, progress invoices; edit flow (terms, disclaimer, save bar), history button to Edits tab, finance role; Job details re-checked after the shared changes (unchanged). Scratch: session scratchpad `inv/`.

## Differs from Pencil / leftovers
- No lifecycle track (Request, Quote, Job, Paid): the invoice read model carries no request, quote or job link. Same trim as Job details. "From job #" omitted for the same reason.
- No "Profit · team only" row: invoices carry no cost data.
- No call/text/directions round buttons (as on Job details); phone is not in the invoice data, so "No phone number yet" still shows.
- "More" stays the three-dot menu, as on Job details.
- Photos and files card is the existing one (no thumbnail grid restyle).
- Money card is light in dark mode (reverse tokens), as on the lists: open question for Jafar.
- Sales role cannot open invoices (403, unchanged); office login failed in the test run, not investigated.

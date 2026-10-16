# A2 Payment details (App look)

Frame: `c696Q` "Payment details · App look · 1440" in classic.pen. Page: `src/routes/(app)/payments/[id=uuid]/+page.svelte`.

## Built
- Page now uses `RecordDetailLayout cards` and an open `PageContainer`, like Job details.
- Header: status pill, "PAYMENT · On N invoices", Send receipt with a mail icon, client row (initials, name, email on one line), four facts with icon tiles (dates drop the year for the current year, as in the frame).
- "Applied to" and "Details" are cards with a one-line hint under the title; invoice rows have an icon tile, link, amount and the outlined row menu.
- Right rail: new `invoices/PaymentReceiptCard.svelte` (what the customer's receipt says, built from the payment's own figures; View receipt and Print or save PDF buttons).
- Shared parts changed (small, additive): `WorkRecordHeader` primary action takes an optional `icon`, status row wraps and buttons never break onto two lines when narrow; `ClientSummaryCard` takes `hidePhone`.
- Behaviour unchanged: all menu items, correction dialogs, correction notes, Send receipt rules, permissions.

## Evidence
Compared live to the Pencil export at 1440 and 1100 wide, light and dark, on real payments (Stripe with a long reference, a plain one with no note, a never-received one). Opened the More menu, a row menu and View receipt (opens the receipt tab). Svelte compiler: no warnings on the four files. No full check/lint run (lead does that).

## Differences from the frame
- No History button: payments have no history panel, so adding it would be a new control.
- "More" is the three-dot menu like Job details, not a labelled "More" button.
- Receipt card shows the business name and logo; the frame's "General contractor" line is left out because the app has no such field.
- The big dashed empty states became one quiet line inside the cards.

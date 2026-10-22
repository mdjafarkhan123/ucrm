# Batches 58 and 59 — Other ways to pay (`s5UUVu` A) and Mark as lost pop-up (`o0HfC` A)

Checked live on 2026-10-22 in a side-by-side dev server on port 5311 (Playwright, 1440 wide; Raad LTD owner and a
temporary customer link to invoice #33, removed afterwards). Compared with the design skill's `cards.md` and
`modals.md` sections.

- `owtp-light.png`, `owtp-dark.png`: the white card on the invoice's blue Balance due panel: title and amount hint,
  five methods with blue tiles (Pay with the external-link icon for Venmo, Cash App, PayPal; Copy for Zelle),
  bank transfer with its instructions in a grey box, and the new foot line naming the business.
- `owtp-copied.png`: Copy pressed → "Copied" with the check on a green button.
- `lost-light.png`, `lost2-dark.png`: Mark as lost on a request card: header tile in the request colour, hint
  "Request · title · client", warning notice strip, Reason, Note with "N / 1,000", Cancel and the red Mark as lost
  with `circle-x`.
- `lost-other.png`: "Other" picked → note label "Note (required for “Other”)", Mark as lost disabled.
- `reason-light.png`: Lost reason from Sales Outcomes on a customer-declined quote: quote-colour tile, "Quote #31 ·
  title · client", "What the customer said" block, lock line, Save reason.

## Checked and not checked

- `npx vitest run src/lib/components/pipeline/MarkOpportunityLostDialog.svelte.spec.ts`: 7 of 7 pass. No type check
  (Jafar: once at campaign end).
- Not driven live: the quote deposit variant of the card (pink edge, "Send the $300.00 deposit", "this deposit"),
  the saving spinner and the couldn't-save strip on the dialog, and a method list with only one entry.

## Changed beside the look

- `OtherWaysToPay` lost its `divider` prop (the card has no line above it); it gained `businessName` and `kind`
  (`invoice` or `deposit`). Venmo, Zelle and e-Transfer have no Tabler brand icon in this version, so `wallet`,
  `send` and `mail` stand in as drawn; the old shared bank icon is now bank transfer only.
- `MarkOpportunityLostDialog` gained a `subtitle` prop (callers: the pipeline card and Sales Outcomes).

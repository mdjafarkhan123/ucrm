# Batches 29–30 — build proof (2026-10-21)

Approved designs: Batch 29 `oxtmi` A (import steps), Batch 30 `TC3iU` A (booking a call). Restyle only: same
steps, fields, words, writes and rules.

## What changed

- Batch 29: new `imports/ImportPage` (760 column, 40 page tile in the import's colour, no eyebrow) and
  `imports/ImportStepCard` (shared Card header, body, pop-up footer bar). `ImportStepper` is one white card with
  icon tiles and joining lines. Upload: file box with the green spreadsheet tile and the sample link with a download
  icon. Map: rows edge to edge, samples under the column name, arrow cell, field box with a green circle-check or a
  yellow warning, unmatched rows tinted with a "Pick one" pill. Review: four count cards with 32 tiles, attention
  and "Nothing gets sent" as notice strips, Import button with a check. Colours: clients `client`, Price book
  `inactive` (book), opening balances `invoice` (receipt). Done screens were not drawn and are unchanged.
- Batch 30: `BookingFrame` (leaf mark, 1080 card radius 24 with soft shadow, host avatar row, Length/How fact tiles,
  chosen time as a Time-coloured box via a new `chosen` prop instead of the `meta` snippet); `BookingMonth` (white
  ringed open days with a green dot, solid green chosen day, 36 bordered ‹ › buttons); `BookingTimePicker` (240
  times column, 44 buttons, hover edge and arrow); `BookingStatus` (56 status tile, white top, facts band, foot band
  with the mail hint or an action); `BookingFacts` (40 tile rows; `framed` on the manage page's view). Details step
  footer: security check left, large Book button with calendar-check right, under a line.

## Screen check (1440, light and dark)

- Imports: checked on the live app (`/clients/import`, `/settings/price-book/import`,
  `/settings/invoices/opening-balances/import`) with a two-row test CSV through Upload → Map → Review (stopped before
  Import, nothing created). Fixed one difference: long step hints were cut off; they now wrap.
- Booking: Jafar's booking is switched off, so the public page shows "Booking isn't open right now" (checked, new
  look). The open states were checked on a temporary fixture page (removed before commit) that ran the real booking
  page with sample times: pick, hover, details, booked, manage view, cancelled, dark. Fixed one difference: the Book
  button sat at the left when no security check is shown.
- Found and fixed afterwards (commit `b2d3ba9f`, Jafar asked 2026-10-21): `/book/manage/[token]` crashed on first render because its time zone started empty; it now starts as the booking's own zone. Regression test `src/routes/book/manage/[token]/page.spec.ts`.

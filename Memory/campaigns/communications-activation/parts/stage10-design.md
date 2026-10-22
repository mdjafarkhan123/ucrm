# Stage 10 design — Pencil screens for global texting

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Order and design
**Stage:** Design
**Code:** none; drawings in `concept.pen` (main folder)
**Done when:** Jafar has approved every Stage 10 screen in Pencil, and the unchosen options are deleted.

## Steps

- [x] Add number pop-up — Jafar approved B 2026-10-22 ("I approved"): guided three steps, with option A's number
  list in step 2 and no cards/list switch. Option A deleted; board `qaFQf` renamed "Concept · Communications ·
  Add number pop-up · Approved B · 2026-10-22".
- [x] States and dark mode drawn on `qaFQf` 2026-10-22 (Jafar: "complete"): Germany paperwork first, Brazil
  nothing to text, searching, no numbers, phone company unreachable, paperwork bill, buying, connection dropped and
  checking, bought. Rules in `.claude/skills/design/modals.md` § Add number pop-up.
- [ ] Compliance list and form — drawn 2026-10-22 on board `A0URqF` "Concept · Communications · Number paperwork"
  (Settings › Phone & SMS › Number paperwork): the list (one row per country and kind, Draft / Under review /
  Approved / Needs a fix with the reason in the row), then a four-step page (country and kind, business details
  filled from the texting registration, documents, check and send). One design: it is a new screen, and
  `guide.md` asks for options only when the app already has the screen. Waiting for Jafar's review.
- [ ] Readiness of each number ("Business details needed", "Under review", "Action needed", "Ready to text").
- [ ] Charges shown before sending or buying.
- [ ] Uplift's internal setup controls (destination permissions done by hand in Twilio).

## Next

Show Jafar board `A0URqF` and wait. On his yes: record it here, rename the board "Approved", draw its states
(empty, loading, couldn't load, uploading / checking / failed file, under review read-only, approved, sending)
and dark mode, then add a "Number paperwork" section to `.claude/skills/design/layout.md`. If `concept.pen` is
uncommitted, ask Jafar for Ctrl+S and commit it from main. The Add number pop-up can be built once its paperwork and readiness
screens are approved, per the plan's order.

## Notes

- Research: GoHighLevel Add Number (country → filters for type, Voice/SMS/MMS, digits → select → Proceed to Buy →
  paperwork prompt) and Twilio Buy a number. Example prices on the board ($2.00 US local, $2.50 toll-free, $6.00 +
  $3.00 setup for Germany mobile) are placeholders; real ones are Jafar's selling prices.

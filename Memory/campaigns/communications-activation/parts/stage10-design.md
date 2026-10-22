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
- [x] Number paperwork (Compliance) list and form — Jafar approved 2026-10-22 ("approved"), board `A0URqF`
  renamed "Number paperwork · Approved". Every state drawn and approved the same day ("approved"), light only (Jafar: "no need to draw dark
  mode"). Rules in `.claude/skills/design/layout.md` § Number paperwork.
- [x] Readiness of each number — Jafar approved B 2026-10-22 ("I see the design B I approved"): summary "2 of 4
  numbers can text" + one card per number with its four-step journey and a status band. Option A deleted; board
  `NbWfA` renamed "Number readiness · Approved B". Every state drawn the same day (page states, summary none/all,
  turned down, just bought, another country on its way, texting paused, ⋯ menu, renaming, sending, saving
  default), light only; Jafar approved the states the same day ("saved, approved"). Rules in `.claude/skills/design/layout.md` § Number readiness.
- [ ] Charges shown before sending or buying — options A and B drawn 2026-10-22 on board `nLAe4` ("Charges
  before sending · Options A and B"), light only, waiting for Jafar's choice. Buying is already covered by the Add
  number bill (`qaFQf`); the board covers the inbox reply box: A = refined cost strip with a destination pill and a
  "What this text costs" pop-over; B = new concept, price on Send ("Send · $0.33"), country pill in the To line,
  segment blocks that fill as you type, balance beside Send. States on both: at home, another country, not enough
  balance (Send off, Add credit → Balance page). New vs live: destination price, balance check before Send.
- [ ] Uplift's internal setup controls (destination permissions done by hand in Twilio).

## Next

Wait for Jafar to pick A or B on board `nLAe4`; then delete the other option, draw the remaining
states (estimating, can't estimate, emoji segments, picture text, automation text) and record the rule in the
design skill. If `concept.pen` is uncommitted, ask Jafar for Ctrl+S and commit it from main.

## Notes

- Research: GoHighLevel Add Number (country → filters for type, Voice/SMS/MMS, digits → select → Proceed to Buy →
  paperwork prompt) and Twilio Buy a number. Example prices on the board ($2.00 US local, $2.50 toll-free, $6.00 +
  $3.00 setup for Germany mobile) are placeholders; real ones are Jafar's selling prices.

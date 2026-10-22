# Stage 10 design — Pencil screens for global texting

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Order and design
**Stage:** Design
**Code:** none; drawings in `concept.pen` (main folder)
**Done when:** Jafar has approved every Stage 10 screen in Pencil, and the unchosen options are deleted.

## Steps

- [ ] Add number pop-up — board `qaFQf` "Concept · Communications · Add number pop-up · Options · 2026-10-22",
  drawn 2026-10-22: Option A (search and pick, one screen; US and Germany-with-paperwork) and Option B (guided
  three steps). Waiting on Jafar's pick.
- [ ] After the pick: delete the other option, then draw every state on the chosen one: searching, no numbers in
  stock, provider unreachable, country with no texting numbers, buying (spinner), interrupted purchase being
  checked, bought → next step; plus dark mode.
- [ ] Compliance list and form (paperwork per country).
- [ ] Readiness of each number ("Business details needed", "Under review", "Action needed", "Ready to text").
- [ ] Charges shown before sending or buying.
- [ ] Uplift's internal setup controls (destination permissions done by hand in Twilio).

## Next

Ask Jafar for A or B on `qaFQf` (and to press Ctrl+S in Pencil), then commit `concept.pen` from main under a
claim. One screen per session: the next session draws the next unticked row.

## Notes

- Research: GoHighLevel Add Number (country → filters for type, Voice/SMS/MMS, digits → select → Proceed to Buy →
  paperwork prompt) and Twilio Buy a number. Example prices on the board ($2.00 US local, $2.50 toll-free, $6.00 +
  $3.00 setup for Germany mobile) are placeholders; real ones are Jafar's selling prices.
- Board drawn from the main checkout's `concept.pen`; Pencil had not saved it to disk when this note was written.

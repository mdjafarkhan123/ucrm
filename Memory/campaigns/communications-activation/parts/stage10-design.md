# Stage 10 design — Pencil screens for global texting

**Campaign:** communications-activation · **Plan:** `docs/global-sms-behavior-contract.md` § Order and design
**Stage:** Design
**Code:** none; drawings in `concept.pen` (main folder)
**Done when:** Jafar has approved every Stage 10 screen in Pencil, and the unchosen options are deleted.

## Steps

- [x] Add number pop-up — Jafar approved B with every state 2026-10-22, board `qaFQf`. Rules in
  `.claude/skills/design/modals.md` § Add number pop-up.
- [x] Number paperwork (Compliance) list and form — Jafar approved 2026-10-22 ("approved"), board `A0URqF`
  renamed "Number paperwork · Approved". Every state drawn and approved the same day ("approved"), light only (Jafar: "no need to draw dark
  mode"). Rules in `.claude/skills/design/layout.md` § Number paperwork.
- [x] Readiness of each number — Jafar approved B with every state 2026-10-22, board `NbWfA`, light only. Rules
  in `.claude/skills/design/layout.md` § Number readiness.
- [x] Charges shown before sending or buying — Jafar approved B 2026-10-22 ("approved", after my recommendation of
  B as drawn, without A's cost card): price on Send ("Send · $0.33"), country and price per segment in the To line,
  segment blocks under the message, balance beside Send; not enough balance turns them red, Send off, Add credit →
  Balance. Option A deleted; board `nLAe4` renamed "Charges before sending · Approved B". Buying is covered by the
  Add number bill (`qaFQf`). Every state drawn the same day under "Every state · drawn on B" (nothing typed,
  working out the price, emoji, picture text, country not switched on, no price yet, couldn't work out the price,
  sending), light only; Jafar approved the states the same day ("saved, approved"). Rules in
  `.claude/skills/design/inputs.md` § Text price in the reply box.
- [ ] Uplift's internal setup controls (destination permissions done by hand in Twilio). Options A and B drawn
  2026-10-22 on board `v6Jtu` ("Uplift texting setup · Options A and B"), light only, waiting for Jafar: A = a
  Texting setup view on the organization's Communications tab (setup journey, countries table with Twilio permission,
  price, status and the row's button; Texting mode and Twilio account side cards); B = a new Platform Operations page
  "Texting setup", an inbox-like to-do queue across businesses with a step-by-step task panel. Shared by both: the
  Countries & prices card (Twilio cost, their price, margin, picture, number a month, businesses, status; a notice
  when Twilio's price moves), replacing the live "SMS retail rates" list.

## Next

Wait for Jafar's pick on board `v6Jtu` (A, B or a mix). On his yes: delete the unchosen option, rename the board
"Approved", draw every state on the chosen one (loading, empty, couldn't load, Mark as turned on saving, Can't turn
on with a reason, set-price pop-up, Twilio price moved), record the rules in the design skill. It is the last Stage
10 screen; after its approval Stage 10 moves to building. If `concept.pen` is uncommitted, ask Jafar for Ctrl+S and commit it from main.

## Notes

- Research: GoHighLevel Add Number (country → filters for type, Voice/SMS/MMS, digits → select → Proceed to Buy →
  paperwork prompt) and Twilio Buy a number. Example prices on the board ($2.00 US local, $2.50 toll-free, $6.00 +
  $3.00 setup for Germany mobile) are placeholders; real ones are Jafar's selling prices.

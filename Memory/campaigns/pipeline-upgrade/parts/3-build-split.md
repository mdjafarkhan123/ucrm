# 3 — Plan: build split

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` (revision 3)
**Code:** `main`
**Done when:** Jafar approves the part list and it is written into `ROADMAP.md`

## Steps

- [x] Read the approved plan and the gap audit
- [x] Check what is already built, so the split covers only what is missing
- [x] Draft 27 build parts in seven stages, riskiest first — `stages/A` to `stages/G`, each marked DRAFT
- [x] Show Jafar the list and ask the two questions below (asked 2026-10-01)
- [ ] Revise the stage files from his answers until he approves
- [ ] Remove the DRAFT lines, add the seven stage rows to `ROADMAP.md`, mark part 3 Done, point `NOW.md` at A1,
      set the `INDEX.md` row to In progress, and delete this note

## Next

Wait for Jafar's answers. Apply his changes to the draft stage files, then finish the last step above. If he
approves push waiting for a later feature, change the Task-alert sentence in the plan's § Opportunity Brief
actions to say in-app alert and email, and add push to **Not doing** with the reason.

## Notes

Already built, so no part covers it: the seven protected stages, forward drag, the Brief with Tasks, Notes,
owner, value and expected close, Lost and Reopen for Requests, automatic Won on quote approval, Won/Lost tiles,
the Sales Outcomes list, salesperson and date filters, the collapsed Assessment setting, Load more, and Task
transfer or completion on convert and Lost.

Stage order: A (custom stages) first because it changes how a card's column is decided and every later board
part builds on it. B touches different code (Request, Quote, and Job commands), so a second session can build
it alongside A.

Questions waiting for Jafar, word for word:

1. "Is any part too big or too small, and is the order right?"
2. "The plan says a Task alert can also arrive as a phone or browser push, following each teammate's
   notification settings. UCRM has no push system and no per-person notification settings yet — they would be a
   new CRM-wide feature, not a Pipeline one. I recommend this campaign builds the in-app alert and the email,
   and push waits for that separate feature. Do you agree, or should push be built inside this campaign?"

Told Jafar, no answer needed: the send window in B3 offers Email and "sent outside UCRM"; Text joins when the
Quotes area can text a quote.

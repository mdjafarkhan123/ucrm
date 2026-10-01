# B5 — Lost and abandoned quotes

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` § Outcomes
**Code:** `main`
**Done when:** Marking an Awaiting response card Lost archives the quote and shows it under Lost with its
value; an archived never-sent Draft adds no Lost; a customer decline shows the customer's message and accepts
a staff reason

## Steps

- [x] Research: how Lost, archive, decline, value, and Tasks work today
- [x] Database change written, applied, and proven with a rolled-back test of every rule
- [x] Server: outcomes list returns reason, note, and the customer's message; new lost-reason route
- [x] Board: "Mark as lost" on Awaiting response and Changes requested quote cards
- [x] Quote page: "Mark as declined" asks what the customer said (optional)
- [x] Sales Outcomes: Lost rows show the reason and the customer's message; "Add reason"; Reopen for quotes
- [x] Unit tests pass; `npm run check` clean
- [x] Browser proof 1: "Staged rail test" (Quote #43) marked Lost from its card; shows under Lost at $198
- [x] Browser proof 3: Quote #38 marked declined with a customer message; Sales Outcomes shows the
      message and took the reason "Price too high"
- [ ] Browser proof 2: archive a never-sent Draft and confirm Lost does not move
- [ ] Close the part: roadmap line, NOW.md, INDEX row, plan wording

## Next

As the contractor owner on Raad LTD, open the never-sent Draft "Tax picker test quote"
(`/quotes/4f7b5f8d-7129-4ed7-9491-103ff88cde27`), choose Archive from its three-dot menu, then confirm
Sales Outcomes → Lost still lists four records and the card has left the Draft column. Then close the
part per the Memory skill. In the plan, § Outcomes, say a decline reaches UCRM when staff record it with
"Mark as declined", which is where the customer's message is typed — ask Jafar first (question below).

## Outside actions

- Database migration `20261002130000` — check: `supabase migration list --linked` shows it on the remote
  side — done

## Notes

- The migration turns Raad LTD's 28 old "Lost" records into Abandoned: all were drafts archived without
  ever being sent. The Lost tile drops accordingly; that is the fix, not a regression.
- Customers cannot decline on the online quote link (it offers Approve and Request changes, as Jobber
  does). A decline reaches UCRM when staff use "Mark as declined" on the quote; that is where the
  customer's message is typed.
- Marking a quote Lost, declining it, or archiving it deletes the card's Tasks (plan § Opportunity Brief
  actions, Jobber). Reopening does not bring them back.
- Question for Jafar, word for word: "Today a customer cannot press Decline on the online quote link —
  like Jobber, the link only offers Approve and Request changes, so a decline is recorded by your team
  with 'Mark as declined'. Is that what you want, or should the customer's own quote page also get a
  Decline button with a message box?"
- The dropdown in the Lost reason window ignores a click made through an accessibility reference in the
  browser tool; click options by position instead. It works normally for a person.

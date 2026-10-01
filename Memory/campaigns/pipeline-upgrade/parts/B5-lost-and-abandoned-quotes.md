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
- [ ] Browser proof on Raad LTD, then close the part (roadmap line, NOW.md, plan wording)

## Next

Prove in the browser as the contractor owner on Raad LTD: mark an Awaiting response card Lost from its
menu and find it under Lost with its value; archive a never-sent Draft from its Quote page and confirm the
Lost count does not move; mark a sent quote declined with a message, then add a reason to it in Sales
Outcomes. Then finish the part per the Memory skill.

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

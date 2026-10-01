# B5 — Lost and abandoned quotes

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` § Outcomes
**Code:** `main`
**Done when:** Marking an Awaiting response card Lost archives the quote and shows it under Lost with its
value; an archived never-sent Draft adds no Lost; a customer decline shows the customer's message and accepts
a staff reason

## Steps

- [x] Research: how Lost, archive, decline, value, and Tasks work today
- [x] Write the database change (`supabase/migrations/20261002130000_lost_and_abandoned_quotes.sql`)
- [ ] Apply it and regenerate `src/lib/database.types.ts`
- [ ] Server: outcomes list returns reason, note, and the customer's message; new lost-reason route
- [ ] Board: "Mark as lost" on Awaiting response and Changes requested quote cards
- [ ] Quote page: "Mark as declined" asks what the customer said (optional)
- [ ] Sales Outcomes: Lost rows show the reason and the customer's message; "Add reason"; Reopen for quotes
- [ ] Tests, then browser proof on Raad LTD

## Next

Apply the migration with `supabase db push --linked` (dry-run first), then work down the steps.

## Outside actions

- Database migration `20261002130000` — check: `supabase migration list --linked` shows it on the remote
  side — pending

## Notes

- The migration turns Raad LTD's 28 old "Lost" records into Abandoned: all were drafts archived without
  ever being sent. The Lost tile drops accordingly; that is the fix, not a regression.
- Customers cannot decline on the online quote link (it offers Approve and Request changes, as Jobber
  does). A decline reaches UCRM when staff use "Mark as declined" on the quote; that is where the
  customer's message is typed.
- Marking a quote Lost, declining it, or archiving it deletes the card's Tasks (plan § Opportunity Brief
  actions, Jobber). Reopening does not bring them back.

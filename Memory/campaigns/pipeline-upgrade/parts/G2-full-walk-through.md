# G2 — Full walk-through

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` (whole plan)
**Code:** `main`
**Done when:** Every rule in the plan is ticked or has a fix; Jafar finishes the tour with no open problem.

## Steps

- [x] Each role's access checked on the live database by acting as that member (rolled back): owner, admin,
      office, sales see and change the Pipeline and its money; field and finance are refused everywhere.
- [x] Cards that left the board (Won, Lost, converted Request, abandoned Draft) refuse value, owner, expected
      close, new or edited Tasks, and Brief Notes. Finishing or deleting a leftover Task and logging a call
      stay allowed. Test: `supabase/tests/database/pipeline_closed_cards_refuse_changes.sql`.
- [x] Every existing Pipeline pgTAP file passes again (four were out of date).
- [ ] Owner walk-through in the browser, phone then desktop (started: phone board, Move menu, Brief open).
- [ ] Office, sales, admin walk-through in the browser; field and finance see no Pipeline.
- [ ] New pgTAP files: custom stages (move, switch off, on hold), Request-to-Job Won, Direct job, the
      `next_task_due_on` trigger.
- [ ] Jafar's own browser tour.

## Next

Carry on the owner walk-through at `http://localhost:5173/pipeline` (Chrome is signed in as the owner,
phone-sized window). Then the other roles: Jafar signs each one in himself — the assistant does not type
passwords into the browser.

## Outside actions

- Migrations `20261006110000` and `20261006120000` pushed to the live database — check:
  `private.pipeline_assert_card_open` exists there — done.

## Notes

- pgTAP runs against the local Docker database with
  `docker exec -i supabase_db_ucrm psql -U postgres -At -q < <file>`. Do not reset that database: it holds
  G1's big fake company. Its migration ledger stops before `20261006100000`; `20261006110000` and
  `20261006120000` were applied to it by hand.
- Waiting on Jafar: "When a Quote is approved (Won), any follow-up Task still open on its card stays open
  forever on the Schedule, and nobody can tick it off because the card's Brief no longer opens. Should
  winning a card finish its open Tasks automatically, the same way losing a Request already does
  (recommended), or should the Schedule get its own tick-off button?"
- Waiting on Jafar (from F2): approve adding the Conversion tab's counting rules to the plan.

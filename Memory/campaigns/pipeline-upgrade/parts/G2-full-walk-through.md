# G2 — Full walk-through

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` (whole plan)
**Code:** `main`
**Done when:** Every rule in the plan is ticked or has a fix; Jafar finishes the tour with no open problem.

## Steps

- [x] Each role's access checked on the live database (rolled back): owner, admin, office, sales use the
      Pipeline and its money; field and finance are refused.
- [x] Cards that left the board refuse Brief changes.
- [x] Every Pipeline pgTAP file passes locally, including three new ones: custom stages (move, on hold,
      switch off), Request-to-Job Won and Direct job, the `next_task_due_on` trigger.
- [x] Owner on desktop: board, search, filters, Table and sorting, bulk tools, Brief, Move menu, mark Lost
      and reopen, on-hold move and Undo, send-quote window (cancelled), Conversion tab, Settings → Pipeline.
- [x] Fixed: owner, Task-owner, and Salesperson lists offered field and finance teammates the database
      refused; the Board/Table switch had no screen-reader name.
- [x] Owner on a phone: everything in the desktop line that applies, plus stage picker, add Task, log call,
      Notes with a photo.
- [ ] Office, sales, admin walk-through in the browser; field and finance see no Pipeline.
- [ ] Jafar's own tour, including dragging a card with a real mouse (forward works, backward is refused).

## Next

Chrome is signed in as the owner at `http://localhost:5173/pipeline`. The other roles are next — Jafar signs
each one in himself; the assistant does not type passwords into the browser, and its fake mouse drag
does not register a drop. For a phone width, `resize_window` on a
fresh tab narrows Chrome to 524; a screenshot after a scroll can stall — retake it.

## Outside actions

- Migration `20261006130000` pushed to the live database and applied by hand to the local Docker
  database — check: `/api/pipeline/teammates` answers for a member with only `pipeline.view` — done.

## Notes

- pgTAP runs against the local Docker database with
  `docker exec -i supabase_db_ucrm psql -U postgres -At -q < <file>`. Do not reset that database: it holds
  G1's big fake company. Its migration ledger stops before `20261006100000`; later files were applied by hand.
- Test data left on Raad LTD: one "No answer" call on a "Pay-by-app verification (copy)" card; a Task "G2
  check: ring back about the quote" due 2026-10-20 on the other copy; "RLS fix check (owner)" was marked
  Lost and reopened twice and carries a note "G2 phone check: note with a photo".
- Photos on Notes stay "Still being checked" here: the local file checker is unhealthy.
- Waiting on Jafar: "When a Quote is approved (Won), any follow-up Task still open on its card stays open
  forever on the Schedule, and nobody can tick it off because the card's Brief no longer opens. Should
  winning a card finish its open Tasks automatically, the same way losing a Request already does
  (recommended), or should the Schedule get its own tick-off button?"
- Waiting on Jafar (from F2): approve adding the Conversion tab's counting rules to the plan.

# G2 — Full walk-through

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` (whole plan)
**Code:** `main`
**Done when:** Every rule in the plan is ticked or has a fix; Jafar finishes the tour with no open problem.

## Steps

- [x] Each role's access checked on the live database by acting as that member (rolled back): owner, admin,
      office, sales see and change the Pipeline and its money; field and finance are refused everywhere.
- [x] Cards that left the board refuse value, owner, expected close, new or edited Tasks, and Brief Notes.
- [x] Every Pipeline pgTAP file passes on the local Docker database, including three new ones: custom
      stages (move, on hold, switch off), Request-to-Job Won and Direct job, the `next_task_due_on` trigger.
- [x] Owner on a phone: board, stage picker, Move menu with reasons, Brief, add Task, log call and "Try again
      tomorrow", Won/Lost report and Conversion tab.
- [x] Owner on desktop: board, search (name, title, phone, email, address), Salesperson filter, Table view
      and sorting, bulk owner and bulk move with their refusal reasons, Brief, Move menu and locked-stage
      reasons, mark Lost and reopen, on-hold move with its future-Task window and Undo, the send-quote
      window (cancelled, nothing sent), Conversion tab, Settings → Pipeline.
- [x] Fixed: the owner menu, bulk Change owner, Task owner list, and Salesperson filter offered field and
      finance teammates the database then refused. They now list only people who may see the Pipeline.
- [x] Fixed: the Board/Table switch had no spoken name for screen readers.
- [ ] Owner on a phone, still to try: Notes with a photo, on-hold move, mark Lost and reopen, search, filters.
      The rules are proven on desktop; only the phone layout is unchecked.
- [ ] Office, sales, admin walk-through in the browser; field and finance see no Pipeline.
- [ ] Jafar's own browser tour, which must include dragging a card with a real mouse (forward onto
      Assessment and onto Draft; backward should be refused).

## Next

Chrome is signed in as the owner at `http://localhost:5173/pipeline`. The window is now stuck at desktop
width (it would not shrink to phone size), so the phone checks need Jafar to drag the window narrow, or
they go on his tour. Then the other roles: Jafar signs each one in himself — the assistant does not type
passwords into the browser. The assistant's fake mouse drag lifts the card and marks the refusing columns
but the drop does not register, so real dragging is Jafar's to try.

## Outside actions

- Migration `20261006130000` pushed to the live database and applied by hand to the local Docker
  database — check: `/api/pipeline/teammates` answers for a member with only `pipeline.view` — done.

## Notes

- pgTAP runs against the local Docker database with
  `docker exec -i supabase_db_ucrm psql -U postgres -At -q < <file>`. Do not reset that database: it holds
  G1's big fake company. Its migration ledger stops before `20261006100000`; later files were applied by hand.
- Test data left on Raad LTD: one "No answer" call on a "Pay-by-app verification (copy)" card; a Task "G2
  check: ring back about the quote" due 2026-10-20 on the other copy; "RLS fix check (owner)" was marked
  Lost and reopened.
- Photos on Notes stay "Still being checked" on this machine: the local file checker reports unhealthy.
- Waiting on Jafar: "When a Quote is approved (Won), any follow-up Task still open on its card stays open
  forever on the Schedule, and nobody can tick it off because the card's Brief no longer opens. Should
  winning a card finish its open Tasks automatically, the same way losing a Request already does
  (recommended), or should the Schedule get its own tick-off button?"
- Waiting on Jafar (from F2): approve adding the Conversion tab's counting rules to the plan.

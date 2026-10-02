# G2 — Full walk-through

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` (whole plan)
**Code:** `main`
**Done when:** Every rule in the plan is ticked or has a fix; Jafar finishes the tour with no open problem.

## Steps

- [x] Database: each role's access checked live (rolled back); cards off the board refuse Brief changes;
      every Pipeline pgTAP file passes locally, three of them new.
- [x] Owner on desktop and on a phone: whole Pipeline, Brief, Sales Outcomes, Settings → Pipeline.
- [x] Office: board, Brief edits, Task, move, Table, outcomes; Settings → Pipeline read-only.
- [x] Fixed: teammate lists offered field and finance; Board/Table switch had no screen-reader name;
      Enter saved the Brief's estimated value twice.
- [x] Sales on desktop: board, Brief edits, Task, call, note, move and Undo, Table, outcomes; Settings →
      Pipeline read-only.
- [x] Admin on desktop: board, outcomes, and a Settings → Pipeline change saved and put back.
- [x] Field sees no Pipeline. Fixed: Settings showed members without the Pipeline its card and stages.
- [ ] Finance sees no Pipeline. As owner or admin, confirm Settings → Pipeline boxes lock while Save runs
      (built, not yet seen in the browser).
- [ ] Jafar's own tour, including dragging a card with a real mouse (forward works, backward is refused).

## Next

Chrome sits on the sign-in page with the finance email typed. Jafar types each password himself (the assistant
never does); the assistant signs out and fills the next email. Its fake mouse
drag does not register a drop. For a phone width, `resize_window` narrows Chrome to 524. Screenshots and
whole tabs often freeze — read the page with `get_page_text` or `javascript_tool`, or open a fresh tab.

## Notes

- pgTAP runs against the local Docker database with
  `docker exec -i supabase_db_ucrm psql -U postgres -At -q < <file>`. Do not reset that database: it holds
  G1's big fake company. Its migration ledger stops before `20261006100000`; later files were applied by hand.
- Test data left on Raad LTD: a "No answer" call and a Task due 2026-10-20 on the two "Pay-by-app
  verification (copy)" cards; "RLS fix check (owner)" sits in Assessment unscheduled with notes, a Busy
  call, a $490 value, the office teammate as Salesperson, and two done Tasks.
- Photos on Notes stay "Still being checked" here: the local file checker is unhealthy.
- Waiting on Jafar: "When a Quote is approved (Won), any follow-up Task still open on its card stays open
  forever on the Schedule, and nobody can tick it off because the card's Brief no longer opens. Should
  winning a card finish its open Tasks automatically, the same way losing a Request already does
  (recommended), or should the Schedule get its own tick-off button?"
- Waiting on Jafar (from F2): approve adding the Conversion tab's counting rules to the plan.

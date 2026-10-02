# G2 — Full walk-through

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` (whole plan)
**Code:** `main`
**Done when:** Every rule in the plan is ticked or has a fix; Jafar finishes the tour with no open problem.

## Steps

- [x] Database: each role's access checked live (rolled back); cards off the board refuse Brief changes;
      every Pipeline pgTAP file passes locally, three of them new.
- [x] Every role checked in the browser: owner (desktop and phone), office, sales, admin; field and
      finance see no Pipeline. Problems found on the way were fixed.
- [x] Jafar's answers built (2026-10-02): a Won card finishes its open Tasks and a reopened win brings
      them back; the Schedule's Task card has a tick box; the Conversion counting rules are in the plan.
- [x] Seen in the browser as owner (2026-10-02): Settings → Pipeline boxes lock while Save runs and refuse
      typing; a Task ticks off from the Schedule, stays done after a refresh, and reopens. Both put back.
- [x] Jafar's tour, round 1 (2026-10-02), all built: filters are hug-width chips (`ui/FilterChip.svelte`);
      a refused drop says why in a centred "Got it" box; the board slides when a card nears an edge
      (`$lib/pipeline/edge-scroll.ts`); the chat button and topic chips are pills, not ovals.
- [ ] Jafar's own tour, round 2: he must try with a real mouse the wider edge-sliding, a refused drop's
      centred box, and picking and clearing a filter chip; then the rest of the tour.

## Next

Wait for Jafar's round-2 tour result; fix what he reports, then close the part and the campaign. For any
browser check, Jafar types each password himself (the assistant never does); the extension lives in Brave.
Its fake mouse drag does not register a drop. When Brave is behind another window the tab stops drawing
and in-page changes look stuck (the address changes, the screen does not): judge a state by reloading its
address. After a reload, click by element ref, not old screenshot coordinates.

## Notes

- pgTAP runs against the local Docker database with
  `docker exec -i supabase_db_ucrm psql -U postgres -At -q < <file>`. Do not reset that database: it holds
  G1's big fake company. Its migration ledger stops before `20261006100000`; later files were applied by hand.
- Test data left on Raad LTD: a "No answer" call and a Task due 2026-10-20 on the two "Pay-by-app
  verification (copy)" cards; "RLS fix check (owner)" sits in Assessment unscheduled with notes, a Busy
  call, a $490 value, the office teammate as Salesperson, and two done Tasks.
- Photos on Notes stay "Still being checked" here: the local file checker is unhealthy.
- Database change `20261006140000` (Won finishes open Tasks) is on the remote and the local Docker database.

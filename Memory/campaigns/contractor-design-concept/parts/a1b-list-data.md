# A1b — list pages show everything their Pencil frames show

**Decision (Jafar, 2026-10-16):** build every piece in the Pencil list frames (`classic.pen`: Clients `TaIwn`,
Quotes `TlErE`, Requests `t7y1t`, Invoices `aBctI`; Jobs `V8myqH` already matches). Not trimming the designs.
**Branch/worktree:** `claude/a1b-list-gaps`, `.worktrees/a1b-list-gaps`. **Model:** Opus for the database slices
(aggregations + speed), Sonnet fine for the screen work. Run the full `npm run check` once at the end, not per slice.

**Rules:** numbers come from the database (RPC or tally, like `quote_status_counts`), never computed in the browser;
money hidden from people without view-price (show a dash); each slice passes `performance-review` design-before,
verify-after; writes none. "More actions" stays disabled with its reason (nothing behind it, intentional).

## Slices (one at a time; commit each)

1. **Clients** — new `GET /api/clients/overview`: counts by Lead/Customer/Archived; top 4 tags with counts;
   new clients last 30 days vs the 30 before, leads last 30 days, new clients this year. Build the Client book card
   and dark "New clients · past 30 days" card (reuse `AttentionCard`/`MoneyFeatureCard`; extend, don't copy).
2. **Quotes** — extend counts: dollar total per status, open total headline, proportion bar; conversion rate 30d vs
   prior, quotes sent (count + $), converted to jobs (count + $). Footer facts: waiting over 7 days (sent_at),
   sent but not opened (`quote_access_links.view_count`), follow-up email days (automation setting). Row second line
   from sent_at, view_count, decided_at/decision_method, converted job number. Changes-requested colour: open
   question in the plan — keep as is until Jafar answers.
3. **Invoices** — footer facts: average days to get paid (30 days), overdue-reminder setting; row second line
   "Viewed N times" / "Not opened yet" from `invoice_access_links`/`InvoiceDelivery.views`.
4. **Requests** — Created date filter (API + `DateRangeChip`), footer facts (assessments today, upcoming booked),
   "Waiting 25 min" second line on the Requested column.

## Done when
Each page matches its Pencil frame at 1440 light and dark with realistic data (seed some for Raad LTD); empty and
loading states fine; focused tests for each new calculation; slice speed check recorded; merged to main.

## Next action
Slice 1: read `quote_status_counts` and `quote_status_tallies` migrations for the pattern, design the clients
overview query and its indexes, then build.

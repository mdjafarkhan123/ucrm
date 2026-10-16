# A1b slices 1 + 4 — Clients and Requests lists (claude-a1b-clients, 2026-10-16)

**Built (branch `claude/a1b-clients-requests`):**
- Clients (`TaIwn`): Client book card (Leads / Customers / Archived tiles that set the Status filter;
  Popular tags strip whose chips set the Tags filter) and the dark New clients card (count, change pill,
  "Became customers, <dates>", New leads · 30 days, New clients this year). New `GET /api/clients/overview`
  (customers.view) over two new RPCs `client_overview_counts`, `client_popular_tags`
  (migration `20261213094217_a1b_clients_overview`, applied and recorded). Windows are 30 calendar days in
  the organization's timezone (`$lib/server/clients/overview.ts`).
- Requests (`t7y1t`): Created date filter (API `created_from`/`created_to`, Zod-checked, + `DateRangeChip`);
  footer facts "assessments today" / "upcoming assessments booked" from the existing `request_status_counts`
  (no migration); conversion card with pill, bar and two rows; "Waiting N min/h/days" under Requested for
  New and Needs approval rows.
- Shared parts extended (additive props only): `MoneyFeatureCard` (`trend`, `details`, `progress`),
  `AttentionCard` (`footer` snippet).

**Evidence:** vitest 17/17 (overview windows, wording, waiting line, conversion pill/bar). Live on Raad LTD:
tile and tag chip filter the list; Created range API returns 2 rows for Oct 1–16 and 422 for a bad date.
Screenshots at 1440/1100, light/dark.

**Speed (20,000 synthetic clients/requests in a rolled-back transaction, RLS as owner, warm):**
overview counts ~15 ms, popular tags ~21–25 ms (run side by side); Created-range list page 2.8 ms
(index range scan on `requests_organization_created_idx`). No new indexes. Nothing seeded.

**Leftovers vs Pencil (not in the slice note):** Requests rows' "Asked for <day>" + time, assessor name,
"Quote #318" under Converted; tile label "Assessment complete" vs Pencil "Ready to quote"; More actions on
Requests stays disabled and greyed.

# A1b — Quotes and Invoices lists (slices 2 and 3)

**Branch/worktree:** `claude/a1b-quotes-invoices`, `.worktrees/a1b-quotes-invoices`. **Claim:** `60007a437201`. **State:** Waiting to merge.

**Built (Pencil `TlErE`, `aBctI`):** Quotes — open total headline, proportion bar, dollar total per status, conversion rate (30 days vs the 30 before), quotes sent and converted to jobs (count and $), footer facts (waiting over 7 days, sent but not opened, follow-up email days), row second lines (sent/viewed/decided/converted). Invoices — footer facts (average days to get paid over 30 days, overdue reminders on/off), row second line "Viewed N times" / "Not opened yet" for sent invoices.
Database: migrations `20261216090000_a1b_quotes_list_overview` and `20261216090100_a1b_invoices_list_facts` (applied and recorded). New `GET /api/quotes/overview`, extended `/api/invoices` and `/api/invoices/counts`. Logic in `src/lib/quotes/list-overview.ts` and `src/lib/invoices/list-facts.ts` with spec files. Shared `AttentionCard` and `MoneyFeatureCard` gained optional options only.

**Checked:** 1440 light as owner against the Pencil frames. Specs and type check NOT run (lead runs once for the batch). The agent had begun a no-price-permission check in a rolled-back transaction; not confirmed. Speed check for these two slices was not recorded; do it at integration.

**Leftovers:** "Changes requested" colour kept as is (open plan question). Dark and 1100 not checked by me. More actions stays disabled by design.

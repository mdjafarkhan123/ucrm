# Part 7 — Jobber parity

**Exact next action:** Jafar approved all five items on 2026-09-28. Build them as slices 7a–7e in a new
temporary worktree (claim `5574f60341e3` points at a removed worktree — release it and re-claim from the new
one). Before each, read its deferred note and load the skills its work needs (svelte, supabase-postgres for
migrations, jobber). Browser-check each on Raad LTD (owner login), commit, then delete its note + INDEX row.

**Approved decisions and slices (suggested model: Opus for 7c–7e, Sonnet fine for 7a–7b):**

- **7a** `request-status-filter-matches-the-stored-status-not-the-displayed-one` — Jafar chose to make the
  filter match the displayed status (not relabel): a view/RPC like `request_status_counts` with the same
  date math, permission-gated like the counts card.
- **7b** `client-detail-page-still-uses-the-superseded-staging-dialog-edit-shape` — rewrite now to Jobber's
  three-edit pattern (`.claude/skills/jobber/jobber-08-screen-patterns.md` § How WE compare); touches
  `clients/[id]/+page.svelte` and `ClientDetailsDialog.svelte`.
- **7c** `quote-composer-has-no-financial-rail-or-proposal-sections` — `/quotes/new` saves a draft on first
  field entry so Discount/Tax/Introduction/Client message attach right there. Careful: changes how quotes
  are created (empty-draft cleanup, double-create guard).
- **7d** `job-visit-card-backend-fields` — store an off-series yes/no marker set when a visit is moved or
  edited alone, plus completed-by. Needs a migration; Jobs-owned, so check the jobs contract first.
- **7e** `no-image-on-a-price-list-item` — one optional picture per price-list item via the File Manager
  catalog (not the legacy `attachments` table), shown on quote lines. Needs a migration.

**Blockers:** none. Do not touch packages (Jafar, 2026-09-27). Part 4 runs in the main folder in another window
(invoices, payments) — use a worktree, and commit only your own paths.

**Pointers:**
- Memory/campaigns/deferred-launch-sweep/ROADMAP.md Part 7

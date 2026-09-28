# Part 7 — Jobber parity

**Exact next action:** finish 7b (WIP committed on the branch, NOT merged). Built: header pencil opens `ClientDetailsForm` in place with its own Save; lead source card edits in place (`LeadSourceEditor`); bar keeps only tags + notes; `⋯` menu → "Edit client details" opens `/clients/[id]/edit` (ClientForm edit mode) in a new tab. Browser-verified: in-place details save (added phone +1 604 555 0100 to Raad's "Tester Account" — remove it again) and lead source editor opens/cancels. Still to do: check svelte-check output, test the `⋯` menu + edit page save, tags/notes bar, then merge, delete the 7b deferred note + INDEX row. Then 7c. Worktree `.claude/worktrees/deferred-sweep-part7b`, branch
`worktree-deferred-sweep-part7b` (it has its own `.env`, `supabase/.temp` and a `node_modules` symlink; a
dev server for browser checks runs from it on `http://localhost:5180`, already signed in to Raad LTD).
Before each slice, read its deferred note and load the skills its work needs (svelte, supabase-postgres for
migrations, jobber). Browser-check each on Raad LTD, commit on the branch, merge into `main`, then delete
its note + INDEX row.

**Done:** 7a (2026-09-28) — merged to `main`; migration `20260928180000` (view `request_list_rows`) applied.

**Approved decisions and slices (suggested model: Opus for 7c–7e, Sonnet fine for 7a–7b):**

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

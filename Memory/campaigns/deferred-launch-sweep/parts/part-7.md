# Part 7 — Jobber parity

**Exact next action:** 7d in progress (Opus). Migration `20260928210000_job_visit_series_date_and_off_series` written on the branch (visits remember their rule date `series_date`; a trigger keeps `off_series`). Outcome check before re-applying: `supabase migration list --linked` shows 20260928210000 remote. Then: add `completed_by_name`, `off_series`, `series_date` to the job-detail read (`src/routes/api/jobs/[id=uuid]/+server.ts`, names via `profiles` like the events endpoint) and `JobVisit`, show them on `JobVisitsSection`, browser-check, merge. Worktree `.claude/worktrees/deferred-sweep-part7b`, branch
`worktree-deferred-sweep-part7b` (it has its own `.env`, `supabase/.temp` and a `node_modules` symlink; a
dev server for browser checks runs from it on `http://localhost:5180`, already signed in to Raad LTD).
Before each slice, read its deferred note and load the skills its work needs (svelte, supabase-postgres for
migrations, jobber). Browser-check each on Raad LTD, commit on the branch, merge into `main`, then delete
its note + INDEX row.

**Done:** 7a (2026-09-28) — merged; migration `20260928180000` (view `request_list_rows`) applied. 7b (2026-09-28) — merged; client details + lead source edit in place with their own Save, bar keeps tags/notes, `/clients/[id]/edit` restored (ClientForm edit mode) from the ⋯ menu. 7c (2026-09-28) — merged; `/quotes/new` has Discount and Tax cards (staged mode) written right after create; browser-checked (test quote #43 on Raad LTD).

**Approved decisions and slices (suggested model: Opus for 7d–7e):**

- **7d** `job-visit-card-backend-fields` — store an off-series yes/no marker set when a visit is moved or
  edited alone, plus completed-by. Needs a migration; Jobs-owned, so check the jobs contract first.
- **7e** `no-image-on-a-price-list-item` — one optional picture per price-list item via the File Manager
  catalog (not the legacy `attachments` table), shown on quote lines. Needs a migration.

**Blockers:** none. Do not touch packages (Jafar, 2026-09-27). Part 4 runs in the main folder in another window
(invoices, payments) — use a worktree, and commit only your own paths.

**Pointers:**
- Memory/campaigns/deferred-launch-sweep/ROADMAP.md Part 7

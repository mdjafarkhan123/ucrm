# Part 7 — Jobber parity

**Exact next action:** 7e in progress (Opus). Migration `20260928230000_catalog_item_photo` committed on the branch and being applied — check with `supabase migration list --linked`; if applied, do not re-run. Next: app code (Zod `image_file_id`, `PUT`-style image set on catalog PATCH, CATALOG_SELECT, files.schema `catalog_item`/`item_photo`, collaboration.ts, CatalogItemDialog upload, picker copies photo onto line, FileDetailsPanel link to price book). Worktree `.claude/worktrees/deferred-sweep-part7b`, branch
`worktree-deferred-sweep-part7b` (it has its own `.env`, `supabase/.temp` and a `node_modules` symlink; a
dev server for browser checks runs from it on `http://localhost:5180`, already signed in to Raad LTD).
Before each slice, read its deferred note and load the skills its work needs (svelte, supabase-postgres for
migrations, jobber). Browser-check each on Raad LTD, commit on the branch, merge into `main`, then delete
its note + INDEX row.

**Done:** 7a (2026-09-28) — merged; migration `20260928180000` (view `request_list_rows`) applied. 7b (2026-09-28) — merged; client details + lead source edit in place with their own Save, bar keeps tags/notes, `/clients/[id]/edit` restored (ClientForm edit mode) from the ⋯ menu. 7c (2026-09-28) — merged; `/quotes/new` has Discount and Tax cards (staged mode) written right after create; browser-checked (test quote #43 on Raad LTD). 7d (2026-09-28) — merged; migrations `20260928210000` + `20260928211000` applied; Visits card shows "Completed … by <name>" and marks a visit moved off its repeat date or given its own time ("Originally <date>"); browser-checked on Job #22 (moved and restored).

**Approved decisions and slices (suggested model: Opus for 7e):**

- **7e** `no-image-on-a-price-list-item` — one optional picture per price-list item via the File Manager
  catalog (not the legacy `attachments` table), shown on quote lines. Needs a migration.

**Blockers:** none. Do not touch packages (Jafar, 2026-09-27). Part 4 runs in the main folder in another window
(invoices, payments) — use a worktree, and commit only your own paths.

**Pointers:**
- Memory/campaigns/deferred-launch-sweep/ROADMAP.md Part 7

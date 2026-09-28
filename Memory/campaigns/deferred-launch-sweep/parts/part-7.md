# Part 7 — Jobber parity

**Exact next action:** 7e is built and MERGED to `main` (`572d7936`); migrations `20260928230000` + `20260928231000` applied (check: `supabase migration list --linked`, do not re-run). Only browser verification is left, then close Part 7:
1. On `https://app.upliftcontractor.com` (tunnel → main dev server on 5173; already signed in as a Raad LTD manager in Chrome), Settings → Price Book → Solar Panel ⋮ → Edit: add a photo in the new photo box, Update item. Confirm the thumbnail shows in the list, in a quote's Price Book drawer and name picker, and that picking the item onto a quote line brings the photo and the quote saves. Also check Files → that photo's "Used in" shows "Solar Panel · Price list".
2. Then delete `Memory/deferred/no-image-on-a-price-list-item.md` + its `Memory/deferred/INDEX.md` row, mark Part 7 done in ROADMAP.md, delete this note, remove worktree `.claude/worktrees/deferred-sweep-part7b` + branch `worktree-deferred-sweep-part7b` (fully merged).

**Gotchas (7e):** photo uploads only work from `localhost:5173` or the tunnel — the R2 bucket's CORS refuses other origins (5180, 127.0.0.1). Never start a second vite server from the worktree: its `node_modules` is a symlink to main's, and it rebuilds the shared `.vite/deps` cache and breaks the 5173 server (fix: `touch vite.config.ts`, then hard-reload). localhost cookies are shared across ports (currently the office test user) — use the tunnel for owner checks. The photo box is only in the Settings (managed) dialog, by design. `npm run check` on the branch: 0 new errors (3 pre-existing "union type too complex" errors in untouched files).

**Done:** 7a (2026-09-28) — merged; migration `20260928180000` (view `request_list_rows`) applied. 7b (2026-09-28) — merged; client details + lead source edit in place with their own Save, bar keeps tags/notes, `/clients/[id]/edit` restored (ClientForm edit mode) from the ⋯ menu. 7c (2026-09-28) — merged; `/quotes/new` has Discount and Tax cards (staged mode) written right after create; browser-checked (test quote #43 on Raad LTD). 7d (2026-09-28) — merged; migrations `20260928210000` + `20260928211000` applied; Visits card shows "Completed … by <name>" and marks a visit moved off its repeat date or given its own time ("Originally <date>"); browser-checked on Job #22 (moved and restored).

**7e build (for reference):** `catalog_items.image_file_id` + triggers keep one `item_photo` file link per item; picking an item copies the photo onto the line (`line_photo_for_save` accepts an active item's current photo); Trash clears it from the item. Shared photo box `src/lib/components/files/PhotoSlot.svelte` (also used by quote lines).

**Blockers:** none. Do not touch packages (Jafar, 2026-09-27). Part 4 runs in the main folder in another window
(invoices, payments) — use a worktree, and commit only your own paths.

**Pointers:**
- Memory/campaigns/deferred-launch-sweep/ROADMAP.md Part 7

# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Done:** Parts 1–6C. Part 6C (line-item photos + global Trash rule) finished 2026-09-23: database
(`supabase/migrations/20260923100000_files_media_line_photos_and_trash_warning.sql`) and frontend
(`ProductsAndServicesBlock.svelte`'s line-photo upload and `FileThumb` tile sizing; `FileDetailsPanel.svelte`'s
three-tier Trash `ConfirmDialog`; `CustomerQuoteDocument.svelte`/`customer-document.ts` removed-photo/file
placeholders; the public `/q/[token]/files/[id]` route's added `trashed_at` re-check) both browser-verified on
Raad LTD (office login: `dev.jafarkhan+office@gmail.com` / `PaidLaunch16!`) — line-photo upload reaching
"Still being checked" with the tile filling its box, the strongest Trash tier on a file a customer already
received, the customer preview showing "Photo removed", and Restore putting it back. Not yet git-committed;
see ROADMAP.md for the full note. `svelte-check` and `prettier --check` are clean on every changed file.

**Not selected yet — three planned parts are equally dependency-ready** (all depend only on 4–5, already
complete): 6D (branding adoption), 6E (messages: reuse only), 6F (marketing asset upload). Ask Jafar which to
build next, or whether Part 7 (customer publication/proof of work) or Part 8 (trash/export/security/scale)
takes priority instead — do not assume an order.

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked".

**Flagged, not fixed:** `requireLinkedEntityAccess` job/visit comment overstates protection; old
`deleteAttachment` call sites not audited; a sales/finance rep who picks then discards a line photo before Save
will fail the orphan-cleanup `trashFile` call silently (no `files.trash`), same as existing best-effort error
handling already tolerates — the file just sits unattached in the library; `npm run check` needs
`NODE_OPTIONS=--max-old-space-size=8192` (3 old "union type too complex" errors, pre-existing, unrelated to
Files and Media); `customer-access.spec.ts`'s "hands over anything that is not a photo" / "shows a line photo"
/ "answers a broken storage read" tests fail on a pre-existing `file_name`/`display_name` mock mismatch,
unrelated to 6C (part of the "73 API unit tests already failing" note from earlier parts).

**Carried to Part 8:** purge must handle published `quote_version_lines.image_file_id` (FK has no ON DELETE)
and protected `file_links` (delete trigger still blocks).

**Pointers:** `docs/files-media-behavior-contract.md`, `Design/Files and Media/README.md`.

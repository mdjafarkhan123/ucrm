# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** Part 5, operational-record adoption. The Client slice (5A) is complete, browser-verified, and
committed. Property is next.

**Exact next action:** Before building the Property slice, resolve where its Files card lives. Unlike Client,
a Property has no detail page — it is only ever edited through `PropertyDialog.svelte`
(`src/lib/components/clients/PropertyDialog.svelte`), which writes immediately and has no id to attach files
to until a new property is first saved. Decide with Jafar (or research Jobber's own pattern) whether Files
belongs inside that dialog (disabled/hidden until the property exists) or needs its own surface, then build
Property the same way Client was built: `RecordFilesCard` with `entityType="property"`, reusing
`detachFileFromRecord`/`attachFilesToRecord` and the existing `/api/files/links` route unchanged.

**Blockers:**

- An upload still cannot be watched turning usable until deployment sets the values in ROADMAP "Approval
  gates" (worker secret, scanner host/port, two Vault secrets, and the cron job that ships switched off).
  Until then every upload correctly stops at "Still being checked".

**What 5A shipped (committed):**

- `20260921230000` (detach command + auto-link on publish) and `20260922090000`, which corrects it: 230000
  replaced the wrong `finalize_file_processing` signature and left a second overload behind. Both are pushed
  to the linked database and `src/lib/database.types.ts` is regenerated.
- `DELETE /api/files/links`, `detachFileFromRecord`, `RecordFilesCard.svelte` (+ 5 passing component tests),
  and the client detail page, which now mounts it instead of `AttachmentsCard`.
- Files left the client page's save bar. Adding happens in the picker dialog and removing in a confirm
  dialog, both of which carry their own button — the design skill's modal exception, not a new pattern.
- Browser-verified end to end on `/clients/<id>` (Raad LTD test org): attach from the picker lands the file in
  the card and bumps its count; the remove confirm dialog reads "Remove `<name>`? This takes the file off this
  client. It stays in your files, and anywhere else it is used keeps it."; after confirming, the file is gone
  from the card but still listed in `/files`. Test attachments made during verification were cleaned up
  afterward.
- `supabase/tests/database/files_record_adoption.sql` passed 17/17 after fixing its `plan(16)` off-by-one
  (17 assertions are written; only the plan count was stale). Run via a local `supabase db reset` +
  `supabase test db` — the first attempt failed because the local stack was mid-reset and missing the last
  three Files migrations; a fresh reset picked them all up.

**Non-obvious risks:**

- The picker's "no access to the library" branch tells the reader they can still upload straight to the
  record, but offers no uploader. Harmless for Client (everyone who can edit a client holds `files.view`);
  it has to be fixed before the Job and Visit slices, where field members land on it.
- `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`; it OOMs otherwise. Three
  "union type too complex" errors in `(app)/+layout.svelte`, `OpportunityBriefDrawer` and `invoices/new`
  are pre-existing `resolve()` route-union noise, not this work.
- `npm run test:unit` still fails 71 tests across quotes, settings and team. All predate this work.
- Several `communications_*` and `automation_6d3` pgTAP files fail on a fresh local rebuild with
  `invalid URL "REPLACE_ME_set_the_real_internal_route_url..."` — a stale placeholder unrelated to Files.

**Pointers:**

- `docs/files-media-behavior-contract.md` — the approved model, including the three reuse decisions
- `Design/Files and Media/README.md` — the workspace blueprint

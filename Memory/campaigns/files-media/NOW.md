# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Active part:** Part 5, operational-record adoption. Client (`0f7b0c9`), Property (`f7010d3`), and Request are
all complete, browser-verified, and committed. Job is next.

**Exact next action:** Mount `RecordFilesCard` with `entityType="job"` on the Job detail page, replacing
whatever attachment mechanism it currently uses, the same way Request replaced its `AttachmentsCard`.

**Blockers:**

- An upload still cannot be watched turning usable until deployment sets the values in ROADMAP "Approval
  gates" (worker secret, scanner host/port, two Vault secrets, and the cron job that ships switched off).
  Until then every upload correctly stops at "Still being checked".

**What Request shipped (committed):** `src/routes/(app)/requests/[id=uuid]/+page.svelte` now mounts
`RecordFilesCard` (`entityType="request"`, `clientId`/`clientLabel` from the request's client) in the rail,
replacing `AttachmentsCard`. Unlike Property, a Request always has its own page and an id from creation, so
there is no saved/unsaved split — it follows the Client shape. Files left the page's save bar entirely:
`pendingFileCount`, `attachmentsCard` state, and the "files last" save step were removed along with it, since
adding/removing now carries its own button (the same modal exception Client and Property use). `npm run check`
is clean (only the 3 pre-existing `resolve()` union-complexity errors) and the files/clients unit tests
(10/10) pass. Browser-verified on `/requests/<id>` (Raad LTD, "Gutter clean with visit" — Marcus Ellison): the
picker offered "On this request", "Marcus Ellison" (client reuse, correctly empty), and All files; attaching
`test-visit-photo.jpg` bumped the card to Files (1) with no dirty-bar prompt; the remove confirm read "This
takes the file off this request. It stays in your files, and anywhere else it is used keeps it."; confirming
showed the "Removed from this request" toast and returned the card to Files (0). Test attachment was cleaned
up after verification.

**Non-obvious risks:**

- The picker's "no access to the library" branch tells the reader they can still upload straight to the
  record, but offers no uploader. Harmless for Client and Request (everyone who can edit either holds
  `files.view`); it has to be fixed before Job and Visit, where field members land on it.
- `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192`; it OOMs otherwise. Three
  "union type too complex" errors in `(app)/+layout.svelte`, `OpportunityBriefDrawer` and `invoices/new`
  are pre-existing `resolve()` route-union noise, not this work.
- `npm run test:unit` still fails 71 tests across quotes, settings and team. All predate this work.

**Pointers:**

- `docs/files-media-behavior-contract.md` — the approved model, including the reuse decisions and each
  slice's placement reasoning
- `Design/Files and Media/README.md` — the workspace blueprint

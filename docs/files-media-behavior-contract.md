# Files and Media Behavior Contract

## Purpose and status

This contract owns the approved contractor File Manager, reusable File behavior, attachments, previews,
customer sharing, deletion, and proof-of-work media. It was approved for planning on 2026-09-21.

The central catalog now exists in the database: `public.files`, `public.file_links`, and
`public.file_folders`, added by `supabase/migrations/20260921160000_files_media_central_catalog.sql` and
proved by `supabase/tests/database/files_media_central_catalog.sql`. Every existing attachment was backfilled
into one File plus one link, reusing its R2 object; `attachments.file_id` records which File each one became.
The old `attachments` path still serves the whole app unchanged — no feature reads the catalog yet.

The upload pipeline now exists too, added by `supabase/migrations/20260921170000_files_media_upload_pipeline.sql`
with `src/lib/server/files/` and `/api/files/uploads`, and proved by 39 pgTAP assertions plus unit tests. An
upload is registered pending, its bytes are read once out of R2 to check size and file signature, compute a
sha256 and stream through ClamAV, and only `finalize_file_processing` can then mark it available.

Preview derivatives now exist too, added by `supabase/migrations/20260921180000_files_media_preview_derivatives.sql`
and `src/lib/server/files/derivatives.ts`. A photo that passes both the signature check and the malware scan is
resized to a 480px JPEG with `sharp`, stored beside its original at `<object key>.thumb.jpg`, and recorded on the
File in the same statement that publishes it. Only `jpg/jpeg`, `png`, `gif` and `webp` under 40 MB get one;
everything else — PDFs, Office documents, text, and an image the decoder cannot read — carries no preview and is
drawn with a typed icon. A preview that cannot be made or stored never delays or blocks the File itself.

The workspace's read side now exists too, added by `supabase/migrations/20260921190000_files_media_catalog_reads.sql`,
`/api/files*` and `src/routes/(app)/files/`. Three `security invoker` functions — `list_files`, `file_usage` and
`list_file_folders` — answer the catalog page, the "Used in" list and the folder rail under the reader's own
policies, so the visible-usage count is taken over the same filtered rows the list is. Browsing, searching,
smart views, folders, the details panel, the lightbox and downloads work.

The write side exists as well, added by `supabase/migrations/20260921200000_files_media_manage_actions.sql`.
Direct upload, rename, move, new folder, Trash and restore all run as service-role commands behind a
permission-checked `/api/files*` route, matching the Part 3 pipeline's posture. Two behaviors are worth
stating here because they are decisions, not mechanics:

- **Renaming keeps the file's extension**, the way Explorer, Finder, Dropbox and OneDrive all do. The name is
  what a download saves as and what the allowlist reads, so "Boiler before" becomes "Boiler before.jpg" and a
  typed "report.exe" on a PDF becomes "report.exe.pdf".
- **Moving a File to Trash detaches it from every record using it**, which is what this contract's Trash
  section calls the confirmed action. The dialog lists those records first. Restoring brings the File and its
  folder back; it does not put it back on them, and the dialog says so. Any File may go to Trash, including one
  a customer already received on a published quote — Part 6C (below) replaced the earlier outright refusal with
  a stronger, named warning and an explicit acknowledgement before that specific Trash goes through.

The reusable record picker exists as well, added by `supabase/migrations/20260921220000_files_media_attach_to_record.sql`,
`src/lib/components/files/FilePicker.svelte`, `FileAttachToRecordDialog.svelte` and `POST /api/files/links`.
Reuse now runs in both directions: the picker takes a record and offers the library, and the details panel's
**Attach to…** takes a File and searches for the record. Three behaviors here are decisions, not mechanics:

- **Attaching is the record's permission, not the library's.** Putting a document on a quote is an edit of
  the quote, so `/api/files/links` checks the same gate the record's own notes and attachments use. That is
  what lets a sales member, who holds `files.view` but never `files.manage`, put a file on the quote they are
  building.
- **Attaching the same File twice is attaching it once.** The command returns the existing link rather than
  failing, so a double-click, or a colleague who attached it a second earlier, is not an error the contractor
  has to read.
- **A new upload started from inside the picker cannot be ticked until its check finishes.** The contract
  already forbids attaching pending content, so the picker lists it with that status and says so in words
  instead of offering a button that must refuse. Linking a record-origin upload automatically once it
  publishes belongs to Part 5's adoption work.

Record adoption has begun with the Client, added by
`supabase/migrations/20260921230000_files_media_record_adoption.sql` (corrected by `20260922090000`),
`DELETE /api/files/links` and `src/lib/components/files/RecordFilesCard.svelte`. A client's file area now
reads the catalog instead of the old `attachments` rows. Three behaviors here are decisions, not mechanics:

- **Taking a file off a record removes one use, never the file.** The confirmation says so in those words,
  and the file keeps every other use. A use the customer has already received is refused, by the same
  trigger that protects it from Trash.
- **A file uploaded from a record joins that record the moment it is published**, inside the statement that
  publishes it. The contract forbids attaching content that has not been checked, so that moment is the
  first one available; doing it in the database rather than the browser means a closed tab cannot lose the
  link. The card says a file is being checked and shows it arriving.
- **Files are not part of a record page's save bar.** Adding happens inside the picker dialog and removing
  inside a confirmation dialog, each of which carries its own button — the same exception a client's
  property dialog already uses — so nothing about a file is left staged and unsaved.

The Property slice followed: `RecordFilesCard` mounts inside `PropertyDialog.svelte` itself, since a Property
has no page of its own — it is only ever edited through that dialog, which already writes on its own button.
Jobber has no property-level files feature to copy, so placement follows the exception above rather than a
Jobber pattern. A new, unsaved property has no id to attach a File to, so the dialog shows "Files can be added
once this property is saved" instead of the card until the property exists; editing a saved property shows the
real card, plus an "On `<client>`" picker section so a file already on the owning client can be reused without
re-uploading. Browser-verified 2026-09-22 (Raad LTD test org).

The Request slice followed the Client shape rather than the Property one: a Request always has its own detail
page and an id from the moment it exists, so `RecordFilesCard` mounts straight into the page rail with no
saved/unsaved split. It replaces the old `AttachmentsCard`, which had been staged through the page's save bar;
files leave that bar for the same reason they left the Client's — adding happens in the picker and removing in
its own confirm dialog, so the bar has nothing left to wait for. The card also takes the request's client as
`clientId`/`clientLabel`, so a file already on that client can be reused without re-uploading, the same reuse
path Property offers. Browser-verified 2026-09-22 (Raad LTD test org).

The Job slice followed the Request shape: `RecordFilesCard` mounts into the page rail with `entityType="job"`,
titled "Photos and files" to match the card it replaced, and takes the job's client as `clientId`/`clientLabel`
for reuse. `canManage` is `can_record_field_records || can_manage_team_field_records` — the same field-record
write right that already gates the job's notes — rather than the card's own default, because a field member may
open a job without being allowed to add to it. Browser-verified 2026-09-22 (Raad LTD test org, owner login):
attach-existing and remove both round-trip correctly and the save bar never appears for files.

Fixed alongside Job: `GET /api/files` gated every view, including `on_record`, behind the library's own
`files.view` permission — contradicting its own comment and the "members can view permitted files" RLS policy,
both of which already say a member reaches a File through a record they can view even without `files.view`.
That gate blocked exactly the members the contract names in the permissions table below: field members, who
hold neither library permission and reach the library only through their assigned job. The route now checks
`on_record` against the named record's own view gate (`requireLinkedEntityAccess`, the same check the record's
notes already use) and keeps the `files.view` gate for every other view, which really is "browse the whole
library." This restores the documented design rather than changing it, so it shipped without a separate
approval round; `npm run check` and the two files component spec files stayed green.

Fixed as Part 5F: uploading a **new** file from inside a record's own picker now follows that record's own
write permission, the same "record's permission, not the library's" rule attaching already used, instead of
requiring the library-wide `files.manage`. `POST /api/files/uploads` checks
`requireLinkedEntityAccess(event, origin_type, 'manage')` for every record-scoped origin
(`client`/`property`/`request`/`quote`/`job_expense`/`job`/`visit`) in addition to `files.manage`; a library
upload (`origin_type: 'file_manager'`) still needs `files.manage` only. `FilePicker`'s Upload button follows
suit: `canUpload = canManageRecord || library's own can_manage`, where `canManageRecord` is the same
record-write value the page already computes for its own save bar. `POST /api/files/uploads/[id]/complete`
dropped its `files.manage` gate entirely and now only checks organization membership — `complete_file_upload`
already restricts completion to the file's own uploader, so the real authorization happened at step one and
the extra gate was only blocking a record-scoped uploader from finishing their own upload, never adding safety.

This closes the Job/Visit gap and, in the same pass, the equivalent one for sales and finance: a sales member
building a quote, who holds `files.view` but never `files.manage`, can now add a fresh file to it the same way
a field member now can to their job — no separate on/off "Files and Media" permission needed, because the
right already being checked is the record's own. Browser-verified 2026-09-22 for Job (Raad LTD, field member
login): the Upload button appears without `files.manage` and an upload reaches "being checked" on the job. The
other record types share the identical backend mechanism but each still needs its own browser pass once its
page carries `RecordFilesCard` — Invoice and Quote adopted it in Part 6A/6B below.

`VisitRecordsDialog` (opened from a visit's "Notes, photos and files" row action) replaces its `AttachmentsCard`
with `RecordFilesCard`, `entityType="visit"`, taking the job's client as `clientId`/`clientLabel` the same way
Job's own card does, with `canManage` the same `can_record_field_records || can_manage_team_field_records`
right. Unlike Notes and the checklist answers this dialog still stages, files leave the dialog's own "Save
records" bar for the reason every other slice already gives: adding happens in the picker and removing in its
own confirm dialog, so nothing about a file was ever waiting to be saved — the dialog's `dirty` check and save
path no longer mention files at all. Browser-verified 2026-09-22 (Raad LTD, field member login, a visit they
are assigned to): the Upload button appears without `files.manage` and the upload reaches
`processing_state = 'pending'` with `origin_type = 'visit'` and the correct `origin_id`, the same "being
checked" outcome Job produces.

**Create-forms need a different shape.** Every slice above edits a record that already exists, so
`RecordFilesCard` can write each add/remove immediately against a real id. A *create* page — `ClientForm`,
`RequestForm`, and recording a brand-new `JobExpenseDialog` entry — has no id yet, and the File Manager cannot
pre-register a File against a record that doesn't exist: `files_origin_id_matches_type_check` requires a real
`origin_id` for every `origin_type` except `file_manager`, and `finalize_file_processing` only links a File to
its record once it publishes. So a create page uses `PendingFilesCard` instead: it stages picked files as
plain browser `File` objects with no server contact, and only calls the real upload pipeline
(`startFileUpload`/`uploadAttachmentFile`/`finishFileUpload`) once the page's own Save hands it the record's
real id — the same external shape (`saveAll(id)`, `discardChanges()`, `onPendingChange`) `AttachmentsCard` had,
matching how Jobber and QuickBooks let a receipt/attachment ride in the same one-button save as record
creation. `JobExpenseDialog` branches on this: correcting an existing expense (`expense` set) uses
`RecordFilesCard` like every other record; recording a new one uses `PendingFilesCard`, saved right after the
write returns the new expense id. Removing an expense's receipt calls `detachFileFromRecord` rather than the
pre-catalog `deleteAttachment`, since the object it points at may be a File shared elsewhere. Browser-verified
2026-09-22 (Raad LTD, office-role login): `ClientForm`'s and `JobExpenseDialog`'s create paths registered a
file against the new record's real id; `RequestForm`'s full save (with a real client picked) did the same;
`JobExpenseDialog`'s edit path showed, added, and removed an existing expense's receipt correctly.

This closes Part 5.

**Part 6A — Invoice.** `InvoiceForm` stages files with `PendingFilesCard` and saves them after the invoice
write returns its id, exactly like `RequestForm`. `fileEntityTypeSchema` in
`src/lib/server/validation/files.schema.ts` is the legacy attachment entity list plus `'invoice'`, used only by
the File Manager's upload/attach/detach schemas; the legacy `attachmentEntityTypeSchema` stays unchanged because
the old `attachments` table never accepted invoices. Browser-verified 2026-09-22 (Raad LTD).

**Part 6B — Quote.** A quote's frozen customer copy now points straight at the File Manager:
`quote_version_attachments.file_id` references `public.files` (backfilled losslessly from
`attachments.file_id`) and replaces the old `attachment_id` foreign key, whose `RESTRICT` was the only thing that
used to stop a sent quote's file from being deleted. That protection now uses the File Manager's own lock: every
`replace_quote_version_attachments` call recomputes `file_links.protected` for the quote, and it is true while
any draft or sent version of that quote still lists the File. Because sent versions are never deleted, a File
that went out on a quote stays locked on it permanently. `replace_quote_version_attachments` only accepts Files
linked to that quote that are `available` and not in Trash. Revising (`clone_quote_version_to_draft`) copies the
frozen rows unchanged; "Create similar" (`create_similar_quote`) also calls `attach_file_to_record` so the new
quote gets its own link. The customer document and the public `/q/[token]/files/[id]` download read
`public.files`. The create form uses one `PendingFilesCard` and the record page one `RecordFilesCard`, replacing
the old separate Attachments and Images sections. Every file linked to the quote is customer-visible, as it
already was in practice. After each add or remove, `syncQuoteVersionAttachments` copies the quote's available
linked Files into the draft version. "Mark as awaiting response" waits for any sync still running, so a file
added right before sending is always included and locked. Per-line photos (`quote_version_lines.image_attachment_id`)
still used the legacy `attachments` table until Part 6C, below. Browser-verified 2026-09-22/23 (Raad LTD): create with a
staged file, attach/detach on a draft, locked after sending, kept after revising, own link after "Create similar",
and a file added then sent within a second is frozen into the sent version and locked.

**Part 6C — line-item photos and the global Trash rule.** `quote_version_lines.image_attachment_id` is
replaced by `image_file_id`, a File Manager File carried forward on revise and "Create similar" the same way
the quote's other attachments are; a published version keeps its line photo's File even after that File is
moved to Trash, which is what lets the customer's copy show the photo as removed instead of silently changing.
`ProductsAndServicesBlock` (the shared request/quote line editor) uploads a line photo through
`startFileUpload`/`finishFileUpload` with `origin_role: 'line_photo'` instead of the legacy attachments
pipeline, and shows it with the same `FileThumb` tile the File Manager itself uses.

The Trash rule changed for every File, not only line photos, settled with Jafar 2026-09-23: **any File may go
to Trash.** The confirmation dialog's severity now grows with how far the File has already reached rather than
refusing outright:

- **Not used anywhere** — a plain confirm.
- **Used on one or more visible records, none customer-facing** — the existing confirm naming those records.
- **A customer already received it on a published quote** — a red/critical dialog that names the affected
  document(s) and requires an "I understand" tick before Confirm enables. `trash_file` still raises SQLSTATE
  P0412 (`acknowledge_customer_copies` not set) so a stale client is caught server-side too; the panel reads
  that refusal and falls back to the same strongest dialog rather than dead-ending on an error.

Trash stays recoverable for 30 days regardless of tier; Restore puts a File back on the same published quotes
it was removed from. The customer's own copy shows a removed line photo or attachment as "Photo removed" /
"File removed" rather than silently dropping it — `quote_customer_document` nulls out a trashed line's
`image_file_id` (keeping `image_removed: true`) and a trashed attachment's `id`/`name`/`mime_type`/`size_bytes`
(keeping `removed: true`), and `CustomerQuoteDocument.svelte` draws the placeholder from those flags. The
public `/q/[token]/files/[id]` route re-checks `trashed_at is null` on the file it serves, on top of the
document's own filtering, since the two are separate queries a Trash can land between.

Carried to Part 8: a published quote's `quote_version_lines.image_file_id` has no `ON DELETE` behavior and
protected `file_links` still block their own delete trigger, so purge must handle both explicitly rather than
relying on an ordinary foreign key.

**Part 7A — Work Report photos.** A job's work report now picks its photos from the File Manager:
`job_report_photos.file_id` replaces `attachment_id` (migration `20260924100000`), and the editor offers every
checked, un-trashed image linked to the job or one of its visits (line photos excluded). A chosen photo gets a
`report_photo` link on the job, kept off the job's own Files card; it is protected while a live (not turned off)
customer link shows it, which gives "Used in" its "customer received" flag and Trash its strongest warning.
Trashing such a photo drops it from the editable report selection; the customer's frozen copy shows "Photo
removed" until Restore brings it back. Turning the link off releases the protection. Already-issued links were
rewritten to name the same pictures by File id. The same migration also fixed "Used in" failing for every File
since 6F: campaign names now come from `public.file_link_marketing_campaign`, mirroring 6E's message lookup.

**Part 7B — Photo captions and labels (decisions approved by Jafar 2026-09-24).** Follows CompanyCam's model;
Jobber has neither (only hand-drawn text on the photo), so this goes beyond Jobber on purpose.

- **One optional caption per File**, written once and shown wherever the photo appears (File Manager, record
  Files cards, work reports). Uploading never asks for one.
- **Labels come from one company-wide list** seeded with Before, During, After, and Damage. People holding
  `files.manage` (owner, admin, office) add, rename, and remove labels; a photo can carry several.
- **Who can caption and label a photo:** anyone with `files.manage`, plus anyone who may add photos to a job
  or visit the photo is on (`field_records.record` / `manage_team`, on a job they can see; a field member sees
  only jobs they are assigned to). Only `files.manage` holders create labels; everyone else picks, and
  captioning grants no rename, move, or trash rights. Built in 7B-1 (migration `20260924120000`,
  `describe_file`, `src/lib/server/files/describe-access.ts`); the shared chip picker is `ui/TagSelect.svelte`.
- **Customer copies stay as sent.** An issued work report link freezes each photo's caption and labels at
  issue time; later edits change only the editable report and future links. Labels freeze as names, so a
  renamed label does not change a sent report.
- **Where they show (built in 7B-2):** under each photo on the work report (editor, Preview as client, the
  customer link), under the file name on File Manager tiles and in the Lightbox, and in search (the caption
  is matched like the file name). The File Manager rail lists every label like a folder; picking one shows
  the photos carrying it. Everyone who may browse the library sees the label list; only `files.manage`
  holders see its edit button.

Decisions settled while building the schema, confirmed by Jafar 2026-09-21 (he asked for the industry-standard, contractor-easy choice):

- **Folders are flat.** The contract asks for optional user folders, not a tree. A nesting column can be
  added later without moving a single file or link.
- **One File is at most 100 MB**, matching Jobber and CompanyCam. The shipped 25 MB database limit is raised to 100 MB in Part 3.
- **Three permissions** govern the library: `files.view` (browse it), `files.manage` (upload, rename, move,
  organize), and `files.trash` (move to Trash and restore). Owner, admin, and office hold all three; sales and
  finance browse only; field members hold none and reach a file through the job they are assigned to.
  Permanent purge stays a background lifecycle action with no user permission.

Writes never reach these tables directly. `authenticated` holds `SELECT` only, `anon` holds nothing, and
every upload, attach, rename, move, share, trash, restore, and purge runs through a server-side command.

`docs/PRODUCT.md` owns the wider product. Communications continues to own channel delivery limits and message
history. Quotes, Invoices, Jobs, and Marketing continue to own what their customer-facing documents publish.

## Core model

- **File** is the manageable organization-owned asset. Its original content is immutable and stored once in
  private Cloudflare R2. Safe thumbnails, video posters, or preview derivatives do not become separate Files.
- **File link** is one use of a File on a CRM record. Reusing a File creates another link, never another copy of
  the original R2 object.
- **Origin** records where the File first entered UCRM: File Manager upload, Client, Request, Quote, Job, Visit,
  Invoice, form, message, catalog item, branding, or another approved workflow.
- **Used in** is the set of distinct CRM records currently linked to the File. Repeated appearances inside one
  record count as one place. A role explains each use, such as attachment, line image, work photo, or report photo.
- Content replacement creates a new File. The user may deliberately relink editable drafts; issued documents and
  historical evidence keep the old File. There is no generic version-history system in the first release.
- Renaming changes the File Manager display name. Customer-facing names already frozen into issued documents do
  not change.

## What enters the File Manager

Every manageable business file uploaded through an approved CRM flow appears automatically. This includes direct
uploads, operational attachments, photos and videos, customer-supplied files, document media, message attachments,
catalog images, logos, and marketing assets.

Security evidence and identity assets that are unsafe or meaningless to reuse—drawn signatures, avatars, internal
delivery payloads, temporary imports, and processing artifacts—remain in their owning feature and do not appear as
ordinary library Files. Their storage still follows the same private-object and retention safeguards.

Direct File Manager uploads are allowed without an immediate CRM link. They show File Manager as their origin and
may be attached later.

## File Manager workspace

Files is a routine main-navigation destination. It provides:

- All files, Recent, Photos, Videos, Documents, Shared with customers, Not attached, and Trash views;
- optional user folders without changing or duplicating record links;
- server search plus filters for type, folder, uploader, date, origin, Client, Property, and record type;
- grid and list views, stable sorting, cursor pagination, and selection-based bulk actions;
- direct upload and a record-aware Attach existing file picker reused by every supported record editor;
- image lightbox, safe PDF preview, native safe video playback, and download rows for other documents;
- rename, move, download, attach, customer-share, move-to-trash, and restore actions when permitted.

Two of those views ship later rather than now, decided while building the workspace on 2026-09-21. **Shared
with customers** needs the explicit-share record that Part 7 creates, and **Videos** needs video on the upload
allowlist, which waits for Part 8's measurements. Neither appears in the rail until its data exists, because a
view that can only ever be empty reads as a broken feature rather than an honest "not yet".

A File belongs to at most one manual folder. Smart views and CRM filters are derived and never behave like extra
copies. Moving a File between folders does not change any attachment.

Search accepts the details contractors are most likely to remember: File name, Client, Property address, Job,
Quote, or Invoice number. The Attach existing picker first offers Files already connected to the current record or
Client, followed by Recent, Photos, Documents, and All files. Not attached contains direct uploads with no current
CRM record link and removes a File automatically when its first link is created.

## File details and “Used in”

Selecting one File opens the existing accessible right-side `SidePanel`, keeping the library and its scroll
position visible behind it. On a narrow screen the same panel fills the viewport.

The panel contains, in order:

1. a useful preview or typed document icon;
2. Download and Attach actions, with Rename, Move, Share with customer, and Trash in the secondary menu as allowed;
3. basic facts: type, size, uploaded by, upload time, origin, folder, and processing state;
4. a prominent plain-language summary such as **Used in 5 places**;
5. a **Used in** list grouped by record type, for example Invoices (3) and Jobs (2).

Each usage row shows the record icon and number/title, Client or Property context, the File's role there, and the
record status when it affects safety. The row links to the real record. The panel initially loads a bounded list
and offers Show more; it does not render an unlimited relationship graph.

The count is the number of distinct visible records, not raw link rows. A user never learns that a hidden record
exists through a total, group count, or label. Owners and authorized all-record users see the complete count.

The panel query stays off until the item is hovered, focused, or selected. Hover/focus prefetches it; a fast click
shows a local skeleton. Closing and reopening uses the TanStack Query cache.

## Permissions and privacy

- Owners and explicitly authorized office users may browse and manage the organization-wide library.
- Other team members see a File only through a record they may already view or through a separately granted Files
  scope. File Manager never widens Client, assigned-Job, financial, communication, or sensitive-record access.
- A File connected only to hidden records is absent from results, counts, search, folders, Recent, and Trash.
- Upload, attach, rename, move, share, trash, restore, and permanent purge are separately authorized server-side.
- All Files are private by default. R2 object keys and long-lived storage URLs are never customer-visible.

## Customer visibility and historical truth

Customer access is always deliberate. Staff select Files for a Quote, Invoice, message, Work Report, or secure
share and preview exactly what the recipient will receive. The File Manager itself is never a customer portal.

Issued Quotes and Invoices, sent messages, signatures, and shared Work Reports preserve the selected File and
customer-facing name/version required by their owning contract. Later renaming, moving, relinking, or uploading a
replacement must not rewrite what the customer previously received.

General selected-file shares are revocable, expire, identify their selected Files, and reveal no other library
content. Live folders or timelines that automatically expose future uploads are outside the first release.

How a selected-file share works (Part 7D, approved by Jafar 2026-09-24; Housecall Pro's selected-attachment
link plus CompanyCam's static Gallery, built on the same hashed-token link the work report already uses):

- **Starting one.** From a File's details panel ("Share with customer") or from a multi-selection in the
  library. Staff choose exactly one Client and how long the link lasts — 7, 30 (default) or 90 days — and see the
  Files and the Client's name before the link is made. At most 50 Files per share. Any available File may be
  shared, including one not linked to that Client; Files still being checked or in Trash cannot.
- **Who may share.** A new `files.share` permission, granted to owner, admin and office.
- **Fixed once made.** A share never gains Files and its expiry never moves. More Files or more time means a
  new share.
- **Delivery.** Copy link, or "Send by email" / "Send by text", which open the Client's inbox conversation with a
  short message and the link written in; staff review and press Send, so it goes through the business's own
  channels and stays in the conversation history. A button is off when the Client has no email address or
  phone number. The draft is handed over in memory, never in the URL, so a reload opens the conversation
  empty. The conversation opens even when it is older than the inbox's latest page or has no message yet.
- **What the customer sees.** The business name and logo, then each shared File by the name it had when
  shared: photos open full size, PDFs preview, every File downloads individually. No captions or labels, no
  "Download all" in the first release, nothing else from the library.
- **Afterwards.** Renaming a File does not change the name the customer sees. Moving a shared File to Trash
  removes it from the customer's page, and the Trash confirmation says how many customers it is shared with.
- **Expired or turned off.** The page says the link is no longer active and gives the business's phone and
  email; no new link is issued automatically. An unknown link is a plain "not found". The phone is the Business
  profile's; the email is the business's enabled sending address (the organization default first), the one its
  customer emails come from. Turning a link off is final.
- **Staff view.** "Shared with customers" in the rail lists shares, newest first: Client, File count, sent,
  expires, whether it was opened, and Turn off; opening one lists its Files. A File's details panel names the
  Clients it is currently shared with. The rail view appears only once the business has a share.
- **Client history.** Creating and turning off a share each add one activity entry on the Client.

## Photos, video, and proof of work

Photos may carry an optional caption and practical label such as Before, During, After, Damage,
Customer-supplied, Serial/model, or Completed. Uploading never requires a label.

Before/after comparison is an explicit presentation assembled for a Work Report, not an automatic guess based on
timestamps. Reports select Files, order them, group them into sections, and may choose pairs. The current Work
Report remains the one proof-of-work product and is extended rather than duplicated.

How arranging works (Part 7C, approved by Jafar 2026-09-24; Housecall Pro photo-report sections plus CompanyCam
before/after pairs, built as a report item rather than a merged image):

- **Sections** are optional headings, each with an optional note. Photos may sit above the first heading; a
  report with no headings looks exactly as it did before sections existed.
- **Starting layout.** Only when a report has no photos chosen yet, added photos are pre-sorted under Before,
  During, After and Damage headings by their first matching label, with the rest under "Other". Labels never
  reorder anything after that. Reports that existed before 7C kept their photos as one list in upload order.
- **Order** is changed by dragging or by up/down buttons. Newly added photos go to the end.
- **A before/after pair** is one report item made of two photos, always labelled Before (left) and After (right),
  each keeping its own caption. Sides can be swapped and the pair split. A photo appears at most once in a
  report, so pairing moves both photos to the pair's place. On a phone the pair stacks, Before on top.
- **The customer sees one fixed layout:** large photos with captions, two across on a desktop and one on a
  phone, with no slider or grid option. Preview as client and Print draw the same document.
- **After sending**, an issued link keeps exactly what the customer was sent. When the report is edited
  afterwards, the job page says so and offers "Copy updated link", which issues a new link and turns the old
  one off.
- Arranging needs the same permission as editing a work report.

Useful contractor photo and document formats are supported through a conservative allowlist. Video support is in
scope, but its first formats, duration, and byte limits must be chosen from measured mobile upload, processing,
playback, and storage evidence rather than copied from a competitor.

## Upload safety and failure behavior

An upload first creates a private pending File. The system verifies size, extension, MIME signature, organization,
and intended operation; scans for malware; creates safe derivatives; then marks the File available. Pending,
failed, or quarantined content cannot be previewed, downloaded, attached, or customer-shared.

The shipped allowlist is `jpg/jpeg`, `png`, `gif`, `webp`, `pdf`, `docx`, `xlsx`, `doc`, `xls`, `csv`, and
`txt`, each with its declared type and real file signature required to agree. Two absences are deliberate, and
Jafar settled both on 2026-09-21:

- **Video** is in scope for the product but not on the allowlist, because this contract requires its formats,
  duration, and byte limits to come from measured evidence rather than a competitor's number. That measurement
  belongs to Part 8, and video becomes its own slice after it rather than shipping on a guessed limit.
- **HEIC**, the format newer iPhones use, is also absent. Nothing in the browser displays it, so it would have
  to be converted on the way in, and the image library the pipeline uses (`sharp`, the Node standard) cannot
  decode it in its shipped binaries: HEIC is HEVC-coded, and the HEVC decoder is left out for patent reasons.
  Supporting it therefore means a second decoder, not a setting. Phones uploading through a web file picker
  normally send JPEG, so this is a gap for files copied off a phone rather than for ordinary photo uploads.
  Jafar chose to leave it out rather than carry a second decoder for a narrow case; it is revisited if a real
  contractor hits it.

A file that fails a check is `failed`; one the scanner flags is `quarantined`, and its object stays in private
storage for the purge sweep rather than being deleted immediately. When the scanner itself cannot be reached,
nothing is claimed and nothing is published: uploads stay pending until it returns, and the failed attempt is
not counted against the file. Uploads whose bytes never arrive are removed after 24 hours, together with any
object they left behind, and never touch a File that carries a link.

Uploads use bounded concurrency, per-file progress, retries, and duplicate-submit protection. A partial batch keeps
successful Files and clearly identifies failed ones. Abandoned or rejected objects are cleaned without deleting an
object referenced by another record. UCRM does not claim offline upload safety until the browser lifecycle and
network-loss cases are implemented and tested.

## Trash, retention, and export

Moving a File to Trash first shows every affected visible record and the consequence. Any File may go to Trash
— settled with Jafar 2026-09-23 — with the confirmation growing stronger as the File's reach grows: unused is a
plain confirm, used on visible records lists them, and a use a customer already received on a published quote
is a named, red/critical warning that requires an explicit "I understand" before it proceeds. See Part 6C above
for the full three-tier rule and how a customer's own copy then shows the loss.

Trash is recoverable for 30 days. Restore returns the File to its previous folder when possible. Permanent purge is
an authorized background lifecycle action that removes derivatives and the original R2 object only after every
retention and reference check passes. Purge is audited.

Complete organization export includes File metadata, link manifests, checksums, and the original permitted blobs.
Export respects the requester's permissions unless it is the separately authorized full-account offboarding path.

## Performance design verdict

- **Growth path:** File rows, links, folders, thumbnails, search results, usage lists, R2 bytes, and concurrent
  uploads grow with organization activity.
- **Workload contract:** pages remain bounded; initial verification uses a deliberately large single-tenant catalog,
  record-link skew, a 50-file upload burst, and supported maximum-size media. This establishes only the measured
  workload, not capacity for 40,000 users.
- **Chosen shape:** indexed tenant-scoped catalog queries, deterministic cursor pagination, batched visible usage
  counts, lazy derivatives, bounded upload/processing concurrency, and no server cache initially.
- **Complexity cost:** central File/link/folder records plus a bounded processing worker. No search engine,
  cross-tenant deduplication, live folder sharing, relationship graph, or generic version history.
- **Failure behavior:** the original stays private and pending until safe; retries are idempotent; an unavailable
  scanner pauses publication rather than exposing unscanned content; tenant permission is checked before every
  metadata or object operation.
- **Verification:** collect query plans/timings for catalog/search/usage reads, response and thumbnail bytes, DOM
  and route weight, upload concurrency/memory, processing backlog/recovery, tenant-isolation tests, and browser
  failure-path evidence.
- **Overall:** product design ready; schema/RLS work and processing-worker infrastructure wait for their campaign
  parts and required approval gates.

## Completion gate

The campaign closes only when every supported upload origin registers one reusable File, existing uploads migrate
without moving or losing R2 objects, every permitted usage is discoverable without leaking hidden records,
customer sharing is explicit and historical documents remain truthful, trash/purge/export are complete, and the
desktop/mobile, security, accessibility, failure, and proportional performance checks pass.

# Files and Media roadmap

**Goal:** One easy contractor File Manager, backed by private Cloudflare R2, where every manageable CRM upload
appears once and stays connected to every record using it.

| Part | Outcome | State | Depends on | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Product contract, domain language, UI blueprint, and performance design | Complete 2026-09-21 | Approved campaign | Jafar approved the complete model, including Used in, contextual search/picker, Not attached, upload reliability, and Shared with customers |
| 2 | Central File/link/folder schema, RLS, permissions, and additive migration plan | Complete 2026-09-21 | 1; fresh coding session; SQL skill gates | Met: 49 pgTAP assertions prove tenant isolation, link truth, protected history, and a re-runnable backfill; migration pushed and 10 attachments backfilled with no R2 object changed |
| 3A | Safe upload, verification and malware scan | Complete 2026-09-21 | 2 | Met: 36 pgTAP assertions plus unit and real-clamd integration tests prove registration, exclusive claiming, earned availability, outage tolerance and the abandoned sweep |
| 3B | Preview derivatives: image thumbnails | Complete 2026-09-21 | 3A | Met: the worker makes a 480px JPEG beside every clean jpg/png/gif/webp under 40 MB with `sharp`, records it through `finalize_file_processing`, and publishes without one for every other type; 39 pgTAP assertions plus unit tests; migration pushed. Lists drawing them is Part 4's gate |
| 4 | File Manager workspace and reusable File picker | Complete 2026-09-21 (`1a84fe1`) — catalog reads, manage actions, reuse (`attach_file_to_record`, `/api/files/links`, `FilePicker`, "Attach to…"), the `/files` workspace, details panel, uploader, nav item. Browse, search, folders, the details panel and attach were checked in the real app; `FilePicker` is proved by component tests and gets its browser pass when Part 5 mounts it | 2, 3A–3B | Desktop/mobile browse, search, folders, details drawer, direct upload, reuse, and Trash pass browser/accessibility checks |
| 5 | Operational-record adoption | Complete 2026-09-22 (`3dfd4aa`) — Client (`0f7b0c9`), Property (`f7010d3`), Request (`0b22d92`), Job and Visit (Part 5F), and 5G/5H/5I's create-form `PendingFilesCard` adoption (`ClientForm`, `RequestForm`, `JobExpenseDialog`) all complete and browser-verified. `QuoteForm`/Quote's record page moved to Part 6 (Jafar's call, 2026-09-22) | 4 | Met: Client, Property, Request, Job, Visit, the `ClientForm`/`RequestForm` intake forms, and `JobExpenseDialog` receipts (both create and edit paths) register/reuse Files with no old-flow regressions |
| 6A | Invoice adoption | Complete 2026-09-22 — `InvoiceForm.svelte` create form and the invoice detail page both browser-verified (create with a staged file, upload succeeds with 0 failures). Found and fixed a real gap along the way: `src/lib/server/validation/files.schema.ts`'s upload/attach/detach schemas were still built on the legacy `attachmentEntityTypeSchema`, which has no `'invoice'` (correctly, since the old `attachments` table constraint never had one); added a new `fileEntityTypeSchema` that widens it with `'invoice'` for the Files-catalog schemas only, leaving the legacy schema untouched | 4–5 | Invoice detail page and create form register/reuse Files like Request does; `file_links.entity_type` gains `'invoice'` |
| 6B | Quote adoption | Complete 2026-09-23 (not yet git-committed) — migrations `20260922130000` + repair `20260922140000` pushed; pgTAP, typecheck, and browser (all 5 checks plus attach-then-send race) pass; behavior recorded in `docs/files-media-behavior-contract.md` | 6A | `QuoteForm` and the Quote record page swap the legacy `AttachmentsCard`/`public.attachments` flow for `RecordFilesCard`/`PendingFilesCard`, preserving the frozen-at-send `quote_version_attachments` behavior |
| 6C | Shared line-item photo migration | Planned | 6B | The one shared `ProductsAndServicesBlock.svelte` (used by Quote, Request, Job, Visit) moves its per-line photo box off `public.attachments` onto the File Manager, in one pass across all four |
| 6D | Branding adoption | Planned | 4–5 | Org logo upload becomes a File Manager entry (Jafar's call 2026-09-22: "File manager should be the main source of all files"), while keeping the existing "old logo stays with an already-sent quote" snapshot rule intact |
| 6E | Messages: reuse only | Planned | 4–5 | Message composer can attach an existing library File without re-uploading; the inbox's own attachment storage/scanning pipeline is left untouched (Jafar's call 2026-09-22) |
| 6F | Marketing asset upload | Planned | 4–5 | Campaign image blocks get a real upload control backed by the File Manager, replacing today's paste-a-URL field |
| 7 | Customer publication and proof of work | Planned | 5–6 | Explicit shares, customer documents, line photos, Work Reports, captions, labels, and comparisons preserve historical truth |
| 8 | Trash, export, security, and scale verification | Planned | 2–7 | Purge/export plus tenant, permission, failure, accessibility, browser, and proportional performance evidence pass |

## Approval gates

- Part 2 changes schema, RLS, and permissions; campaign approval covers the direction, but implementation starts
  only in a fresh coding session after loading the SQL/Supabase gates.
- The `files_available_means_verified_check` fix Jafar approved for Part 5 was applied early, in Part 4B
  (`20260921210000`), because `not valid` still enforces on every UPDATE and so blocked renaming, moving or
  trashing any file a contractor has today. Scoped to the pipeline's own `<organization>/files/` prefix and
  validated, exactly as approved. Part 5 no longer owes this.
- Part 3 topology approved 2026-09-21 and built as approved, with one deliberate simplification: an upload keeps
  one storage key for its whole life instead of being copied from a waiting prefix to a final one. Every object is
  private in R2 either way, RLS hides a File that is not available, and the single key removes a copy of up to
  100 MB per upload and the orphan class a failed copy would create. Checks, promotion and the abandoned sweep run
  in the existing app container through an internal route woken by pg_cron/pg_net; one private ClamAV container
  beside the app; no Redis/BullMQ. Anything beyond this needs fresh approval.
- Before Part 4 can show uploads working, deployment must set `FILES_PROCESSING_WORKER_SECRET`,
  `FILES_SCANNER_HOST`/`FILES_SCANNER_PORT`, the two Vault secrets
  (`files_processing_worker_target_url`, `files_processing_worker_secret`), and activate the
  `files-processing-worker-wake-one-minute` cron job, which ships switched off.
- Both open format decisions settled by Jafar 2026-09-21: HEIC stays off the allowlist (sharp's shipped binaries
  cannot decode HEVC, so it would need a second decoder for a narrow case), and video waits for Part 8's
  measurements and then becomes its own slice. Neither is rediscovered work; both are recorded in the contract.
- No capacity claim follows until Part 8 measures and states the tested workload.

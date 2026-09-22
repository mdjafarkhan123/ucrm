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
| 5 | Operational-record adoption | In progress — Client (`0f7b0c9`), Property (`f7010d3`), and Request are complete and browser-verified. Job is next | 4 | Client, Property, Request, Job, Visit, forms, and expenses register/reuse Files with no old-flow regressions |
| 6 | Commercial and communications adoption | Planned | 4–5 | Quotes, Invoices, line/catalog media, messages, branding, and marketing assets register once and preserve owning-domain rules |
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

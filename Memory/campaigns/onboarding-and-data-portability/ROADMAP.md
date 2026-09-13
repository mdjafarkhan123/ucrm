# Onboarding & Data Portability Roadmap

Owns launch-roadmap Step 2 (`docs/crm-launch-implementation-roadmap.md` § 2): safe assisted import in, safe
export out. Proven pattern + our own divergences: `docs/research/onboarding-import-export-research.md`.

Standard: 5-step wizard (Type → Upload → Map → Details → Result). Our hard email+phone uniqueness forces
dedupe rules HubSpot does not need. No import may trigger customer messages/automations/reviews/dunning.

| Part | Outcome | State | Depends on | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Import clients + contacts + linked properties: upload → column-map (auto + editable) → preview with dedupe/error flags → idempotent batch → per-row result/error file | Approved 2026-09-13; not started | Launch Step 1 access rules (done); existing `create_client` + `duplicates.ts` | Real file imports twice with zero duplicates; every rejected row explainable; no customer-facing side effect fires |
| 2 | Export those same records: structured package (records + relationship IDs + files manifest), permission-filtered, short-lived link, self-contained download | Planned | Part 1 | An outside person opens the package and reads usable, linked records; link expiry does not break the file |
| 3 | Price Book import + export (`catalog_items`), reusing Part 1 pattern | Planned | Part 1 | Catalog items round-trip cleanly; no duplicate services |
| 4 | Opening balances (one model: unpaid invoices OR starting balance, never both) | Blocked | Launch Step 3 financial-reconciliation audit | No double-counting; no dunning triggered; reconciles from source to screen |
| 5 | Assisted onboarding checklist + internal runbook | Planned | Parts 1–3 | The assisted move-in is guided and repeatable |

## Part 1 build decisions (locked 2026-09-13, plan approved)

- Placement: Clients list "More actions" menu → `/(app)/clients/import`. Screens = approved artifact (Upload →
  Map → Review → Done).
- File format: CSV first (Papaparse — the one new dependency); XLSX is a fast-follow, not Part 1.
- Match action: Skip **or** Update (per-import operator choice; Update honors the Map screen "don't overwrite"
  toggles).
- Reuse only: `create_client` RPC (verified: fires NO customer-facing events — only internal activity log +
  geocode flag), `findExactDuplicates` + the `client_contact_methods_org_value_unique_idx` unique index,
  `clientWriteSchema`.
- Async: two private tables `import_batches` + `import_rows`; `process_next_import_row` RPC with
  `for update skip locked`; drained by a worker mirroring `submission-worker.ts` + pg_cron wake. Resumable +
  crash-safe; row status guards against double-create.
- Perf: Review does ONE batched dedupe query (not per-row) + in-memory in-file dupe detection; enforce ~5,000
  row / 2.5 MB cap. Verify: EXPLAIN on batched dedupe + real file imported twice = zero dupes.
- Build order: (1) DB migration + RPC + cron, (2) upload/parse API, (3) map API, (4) review dry-run API,
  (5) commit + worker + error file, (6) the 4 screens.

## Dedupe/retry rules (Part 1 — from research doc)

- Match on normalized email/phone (DB-unique per org). Match → Skip or Update existing; never "import anyway".
- Shared phone/email across rows → first wins the method; later rows import without it, flagged.
- Email-vs-phone match conflict → held out for a human, never guessed.
- No email + no phone → imports as new, tagged source-file+row-id (that tag is the idempotency/retry key).
- Batched + resumable; a crash mid-run never double-creates.

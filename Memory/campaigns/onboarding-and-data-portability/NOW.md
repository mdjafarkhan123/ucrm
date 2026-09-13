# Onboarding & Data Portability: Current Checkpoint

## Goal

Safe assisted import of a new contractor's core records (no duplicates) and full export out — launch-roadmap
Step 2, the second unstarted gate before the first paying customer.

## Where things stand

Part 1 (client import) in build; locked order in ROADMAP "Part 1 build decisions". Design signed off — 4-step
preview (Upload → Map → Review → Done) at `Design/onboarding/import-clients.html` is the source of truth for
the step-6 screens (load `design` + `svelte` only then). CSV-first + Papaparse and Skip-or-Update approved.

Locked invariants (foundation migration `20260916090000_client_import_foundation.sql`): `import_batches` +
`import_rows` are RLS SELECT-only, NO insert policy — every write is a SECURITY DEFINER /api RPC (rule 12), so
the `authenticated_security_definer_function_executable` WARN is BY DESIGN; always `revoke execute … from anon`
on each write RPC. Schema hard-uniques email AND phone per org (dedupe differs from HubSpot's email-only). Types:
regenerate via MCP tool + prettier (CLI `db:types` clobbers). Retry/idempotency key is `(batch_id, source_row_number)`.

- **Steps 1–3 DONE & committed** (git `d8f0dcc`): tables; upload `POST /api/imports/clients`; map
  `PATCH /api/imports/clients/[batchId=uuid]`.
- **Step 4 DONE (UNCOMMITTED)** — `POST …/review`: `match_import_clients` (invoker read, batched array-param
  dedupe) + `review_import_batch` (definer write). Pure engine `src/lib/server/imports/review.ts` (33 tests).
  Writes every row `pending_review`; imported clients are `lifecycle_status 'customer'`; `resolved_payload`
  contract (incl. `initial_note`) is documented on the `import_rows.resolved_payload` column comment.
- **Step 5a DONE (UNCOMMITTED)** — `commit_import_batch(payload {batch_id, consent_affirmed})`, migration
  `20260916130000_client_import_commit_rpc.sql`. Refuses without consent (check_violation) + stamps
  `consent_affirmed_at`; one set-based pass flips `pending_review`: create/update→`ready`, skip→`skipped`,
  hold→`held`, error→`failed`; seeds skipped/held/error counts (created/updated stay 0 for the worker); batch
  reviewed→`importing` (or straight to `completed` when nothing to drain). Route `POST …/commit` (Zod
  `importClientsCommitSchema`; errcodes P0002→404, 42501→403, 23514→consent 422, 22023→422). 10 route tests.

## Next action

**Step 5b = worker + error file.** (1) `process_next_import_row` claim RPC: `for update skip locked` on
`import_rows_ready_idx`, executes `resolved_payload` via the INLINED create-client sequence (NOT `create_client`
— it is security-invoker/auth.uid; worker runs as service_role; set note `created_by` = batch `created_by`),
maintains the batch's create/update counts, finishes the batch (`importing`→`completed`), crash-safe/idempotent
on `(batch_id, source_row_number)` — mirror `process_next_form_submission` (never raises; records row failure).
(2) TS drain module + secret-gated internal endpoint mirroring `submission-worker.ts` +
`/api/internal/forms/worker` (new `CLIENT_IMPORT_WORKER_SECRET`). (3) Per-row error file (R2 `putObject`,
`error_file_object_key`) for the Done screen. **Wake (Jafar: follow industry, no overengineering):** use the
proven in-repo automation-worker pattern — best-effort nudge fn on commit + an INACTIVE once-a-minute pg_cron
sweep as the guarantee (activated at deploy); the forms worker's missing cron is a gap, not the model. **Known
edge:** a row Review predicted `create` colliding with a *restorable* (soft-deleted) client hits
`client_contact_methods_org_value_unique_idx` (23505) — catch it, mark the row failed with a plain "duplicate of
a client you deleted" line in the error file. Completion gate: real file imports twice with zero duplicates;
every rejected row explainable; no customer-facing event fires.

## Blockers

None for Part 1. Part 4 (opening balances) is blocked on the launch financial-reconciliation audit (Step 3).

## Env notes

- Test HubSpot portal `244841066` holds 3 harmless test contacts Jafar can delete anytime.
- Dev server: svelte-check OOMs (use targeted `tsc`); clear `.vite` on a blank page.

Resume command: `continue onboarding and data portability`.

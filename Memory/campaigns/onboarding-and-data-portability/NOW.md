# Onboarding & Data Portability: Current Checkpoint

## Goal

Safe assisted import of a new contractor's core records (no duplicates) and full export out — launch-roadmap
Step 2, the second unstarted gate before the first paying customer.

## Where things stand

Part 1 (client import) in build, locked order in ROADMAP "Part 1 build decisions". Design signed off —
approved 4-step preview (Upload → Map → Review → Done) saved in the repo at
`Design/onboarding/import-clients.html` (source of truth for the step-6 screens). CSV-first + Papaparse and
Skip-or-Update approved. Screens are step 6 — load `design` + `svelte` only then.

Locked design fact (step 1 migration `20260916090000_client_import_foundation.sql`): `import_batches` +
`import_rows` have RLS SELECT only, NO insert policy — every write is a SECURITY DEFINER /api RPC (rule 12).
So the `authenticated_security_definer_function_executable` advisor WARN on those RPCs is BY DESIGN; close the
anon variant (`revoke execute … from anon`, like 20260913120000). `resolved_payload` worker contract is locked
in that migration's column comment. Our schema hard-uniques email AND phone per org
(`src/lib/server/clients/duplicates.ts`), so dedupe differs from HubSpot (email-only).

- **Step 1 DONE** — the two tables + claim index. Claim RPC + pg_cron wake deferred to step 5 on purpose.
- **Step 2 DONE** — `POST /api/imports/clients` (+ spec, 10 tests): multipart CSV → Papaparse
  (`header:true`, `transformHeader` trims) → headers + 20-row preview + row_count → `putObject`
  (`buildClientImportObjectKey`) → `create_import_batch` RPC → `{ batch_id, headers, preview_rows, row_count }`.
  Over 2.5 MB / 5,000 rows REJECTS. Migration `20260916100000_client_import_upload_rpc.sql` applied; types
  regenerated via MCP (CLI `db:types` needs a login token, clobbers the file — use the MCP tool + prettier).
- **Step 3 DONE** — `PATCH /api/imports/clients/[batchId=uuid]` (+ spec, 12 tests) → `set_import_batch_mapping`
  RPC (migration `20260916110000_client_import_mapping_rpc.sql` applied). Persists `column_mapping`
  (header → { field, dont_overwrite }) + `match_action`, moves status uploaded/mapped → mapped. Zod
  (`src/lib/server/validation/imports.schema.ts`, `IMPORT_CLIENT_TARGETS`) gates targets, rejects empty map +
  duplicate targets. Industry-grounded decisions (per `onboarding-import-export-research.md`): NO
  minimum-contact gate (name-only rows import as new; retry-safety is the `(batch_id, source_row_number)`
  unique key, not a required match key); `initial_note` IS a target (existing client field + signed-off
  design) — so step 4's `resolved_payload` must carry `initial_note`. RPC errcodes mapped in route: P0002→404,
  42501→403, 22023→422.

## Next action

**Step 4 = review dry-run**: a SECURITY DEFINER RPC behind `/api` that re-reads the file from R2, applies the
saved `column_mapping`/`match_action`, runs dedupe (`src/lib/server/clients/duplicates.ts`; email AND phone
are match keys — our divergence from HubSpot), and writes one `import_rows` row per data row with
`planned_action` (create/update/skip/hold/error) + `resolved_payload` (see locked contract in the step-1
migration column comment — ADD `initial_note` to it). First-row-wins on a shared phone within the file;
email↔phone conflict → hold. Moves status mapped→reviewed. Nothing is written to `clients` yet (that is
step 5, the worker).

## Blockers

None for Part 1. Part 4 (opening balances) is blocked on the launch financial-reconciliation audit (Step 3).

## Env notes

- Test HubSpot portal `244841066` holds 3 harmless test contacts Jafar can delete anytime.
- Dev server: svelte-check OOMs (use targeted `tsc`); clear `.vite` on a blank page.

Resume command: `continue onboarding and data portability`.

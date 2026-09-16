# Onboarding & Data Portability: Current Checkpoint

## Goal

Safe assisted import of a new contractor's core records (no duplicates) and full export out — launch-roadmap
Step 2, the second unstarted gate before the first paying customer.

## Where things stand

**Parts 1–3 and 5 are all DONE, COMMITTED-PENDING, and browser-verified.** Part 4 (opening balances) is
**built but not yet browser-verified**, and not yet committed to git. Campaign is **Paused** mid-Part-4 —
paused by Jafar 2026-09-16 for a session switch, not blocked.

Built this session (typechecked clean via `svelte-check`, unit-tested via `vitest`, `prettier`/`eslint` clean
on every touched file):

- Migration `supabase/migrations/20261004100000_opening_balance_import_screens_rpcs.sql` — **applied to the
  remote database already** (via the Supabase MCP `apply_migration` tool), not yet committed to git. Adds
  `create_opening_balance_import_batch`, `commit_opening_balance_import_batch` (no consent gate — an opening
  balance never contacts a customer), `match_active_opening_balances` (dedupe/correction read), and widens
  `set_import_batch_mapping` + `review_import_batch` (shared with the client importer) to pick the write
  permission from a new `private.import_batch_entity_permission(entity_type)` helper instead of a hardcoded
  `customers.create` — this is what makes an opening-balance batch require `invoices.create` instead.
- `src/lib/server/validation/imports.schema.ts` — added `IMPORT_OPENING_BALANCE_TARGETS` +
  `importOpeningBalancesMappingSchema` (no `dont_overwrite`, no `match_action` — a match is always a
  correction).
- `src/lib/server/imports/opening-balance-review.ts` (+ `.spec.ts`, 9 passing tests) — the pure Review
  dry-run: resolves each row's client by email (via the existing `match_import_clients` RPC), decides
  create vs. correction from `match_active_opening_balances`, holds a second file row that targets the same
  {client, balance_type} pair in one run ("never guessed" — mirrors the client importer's
  email/phone-conflict hold).
- `src/routes/api/imports/opening-balances/**` — upload, `[batchId]` GET/PATCH, `review`, `commit`,
  `error-file`. All gated on `invoices.create`. Currency is always the org's own locked currency
  (`organizationFormatting`), never read from the file.
- `src/lib/imports/opening-balance-api.ts` — browser API + header auto-mapping, mirrors `$lib/imports/api.ts`.
- UI: extended the shared `ImportUploadStep`/`ImportMapStep` with `showMatchAction`/`showOverwriteToggle`
  props (opening balances has neither concept) rather than forking them; added `OpeningBalanceDoneStep.svelte`
  as its own component (same reason Part 3's Price Book got its own Done step — different runtime shape).
  Wizard page: `src/routes/(app)/settings/invoices/opening-balances/import/+page.svelte`. Entry point added
  to `src/routes/(app)/settings/invoices/+page.svelte` ("Opening balances" section, owner/admin-visible via
  the route's own permission gate).
- Sample file: `static/samples/opening-balance-import-sample.csv`.

## Next action

**Browser-verify end to end**, then commit. Log in as an Owner/Admin (role matrix — only Owner/Admin hold
`invoices.create` by default), go to Settings → Invoices → "Import opening balances", and walk Upload → Map →
Review → Done with the sample CSV against two real clients that already exist in that org. Confirm: (1) a
fresh receivable/credit imports clean; (2) re-importing the same client+type becomes a correction (Review
shows it under "New balances" vs. a correction count, not a duplicate); (3) two rows in one file for the same
client+type both show up and the second is held, not silently guessed; (4) an unknown email errors with a
plain message; (5) the Done screen's counts and "these balances now show on each client's account" hold up —
spot-check the client detail page's balance actually moved. Then run `npm run test:unit` for the whole repo
once (not just the new file) to make sure nothing else regressed, and commit every file this session touched
(see the list above — do NOT touch or commit `src/lib/components/quotes/CustomerQuoteDocument.svelte`,
`src/lib/database.types.ts`, `src/lib/quotes/customer-document.ts`,
`src/routes/(app)/quotes/[id=uuid]/preview/**`, `src/routes/(public)/q/[token]/**`,
`supabase/migrations/20261003110000_quote_branding_freeze.sql`,
`supabase/tests/database/quote_branding_freeze.sql` — those are a different, concurrent agent's
`quote-branding` work on this same branch, not part of this campaign).

When Part 4 closes, return to `Memory/campaigns/crm-launch-readiness/NOW.md`: Part 2 becomes complete, update
its nine-part status, and it auto-selects Part 4 (minimum website speed-to-lead) next.

## Blockers

None — build is done, only verification and commit remain.

## Essential pointers

- `docs/financial-reconciliation-contract.md` ("Opening balances")
- `supabase/migrations/20261004100000_opening_balance_import_screens_rpcs.sql` (this session's migration,
  already applied remotely, not yet in git history as a commit)
- `src/lib/server/imports/opening-balance-review.ts` (the dedupe/correction rules, unit-tested)
- Test-only Raad LTD logins in `CLAUDE.md` if a non-owner permission scenario needs checking (office role
  should NOT be able to import opening balances unless separately granted `invoices.create`)

Resume command: `continue onboarding and data portability` (or just `continue crm launch readiness`).

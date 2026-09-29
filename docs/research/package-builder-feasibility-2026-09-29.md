# Package builder feasibility check

Read-only source review, 2026-09-29. The approved behavior is feasible in the current SvelteKit and Postgres application, but substantial replacement is required. This is a design feasibility check, not an implementation test or capacity claim.

## Existing foundation

Published package versions and organization assignment history exist. The access resolver reads assigned versions and organization overrides; the owner has manual payment, correction, refund, and paid-through commands. The app has member invitations and seat counting. Feature-specific limits exist for operational/essential email, marketing email, website chat, and automation. Sources: `src/lib/server/access/effective.ts`, `src/lib/server/validation/access.schema.ts`, `src/lib/server/validation/owner.schema.ts`, and `supabase/migrations/20260101000000_baseline_structure.sql`.

## Required replacement

- The database and TypeScript restrict package keys to Starter, Growth, and Elite. The package page and API only edit existing identities. Remove fixed-tier assumptions across storage, validation, owner UI, and access resolution before arbitrary creation works.
- Stored package versions accept only monthly USD prices. USD can stay; independently published monthly/yearly prices and introductory offers need new data and owner controls.
- Current draft save uses several separate writes. A complete save needs one atomic operation; publishing must review the saved revision and reject a stale or dirty draft. Preserve assigned versions through archiving and later restoration.
- Current commercial history records USD receipt-like events and paid-through changes, but does not model each amount due, payment allocation, credit balance, or promotion claim as the new plan requires. Build these as distinct records with history and safe retries; keep contractor invoice/payment records separate.
- Seat counts currently include active/pending members and reserving invitations, including the owner. The approved rules align with that. Yearly monthly usage boundaries and mid-period edition changes require verified feature-specific handling.
- Feature catalog labels are not proof of complete product behavior. Verify each selectable extra end to end; do not publish unverified dispatch/API items or other catalog-only promises.

## Verification before completion

Use a fresh local database and focused end-to-end scenarios for package create/copy/publish/archive/restore, assigned retired editions, simultaneous draft saves, interrupted full saves, offsite receipts/credits/corrections, promotion expiry, month/year boundaries, access after grace, and downgrade consequences. Reconcile historical test assignments and the deferred email-allowance mismatch before live use. Before any remote database change, check the new migration with a dry run as the project requires.

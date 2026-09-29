# P4a — Billing ledger in the database

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § Offsite payment and coverage · ADR 0003 decision 6
**Code:** `main`
**Done when:** `supabase/tests/database/package_billing_ledger.sql` passes on a fresh local rebuild and the migration is on the live database.

## Steps

- [x] Migration `supabase/migrations/20260930100000_package_billing_ledger.sql` written; applies on a fresh local rebuild
- [x] Ledger test (35 checks) passes; purge test moved onto the ledger; old 6B late-renewal test deleted. Other full-suite failures are the known stale ones (placeholder Vault URLs, old function signatures)
- [ ] Push the migration to the live database
- [ ] Regenerate `src/lib/database.types.ts`, run `npm run check`, commit, close P4a

## Next

Run `npx supabase db push --linked --dry-run`, confirm only `20260930100000` is pending, then push.

## Outside actions

- Live migration `20260930100000_package_billing_ledger` — check: `select version from supabase_migrations.schema_migrations where version = '20260930100000'` — pending

## Notes

- Decisions inside the approved plan: charges form a chain (the next starts the day after the last; a start date is only given for the first charge or after a break); only the latest unpaid, uncovered charge can be cancelled; coverage needs the charge fully paid and the exact period dates; a payment correction cancels the original and re-applies the replacement to the same charges; the late-renewal command is dropped and P5 rebuilds reactivation.

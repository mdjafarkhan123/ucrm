# P5a — Pause and free access in the database

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § Offsite payment and coverage
**Code:** `main`
**Done when:** the pgTAP test proves eight days past paid-through pauses, coverage restores at once, a security pause stays after payment, free access prevents and lifts a nonpayment pause; migration on the live database

## Steps

- [x] Migration `20260930140000_package_grace_pause_and_free_access.sql` and test `package_grace_and_free_access.sql` (31 pass locally); older fixtures given dated free access
- [ ] Push the migration to the live database
- [ ] Regenerate database types, run `npm run check`, commit, close P5a

## Next

Push with `npx supabase db push --linked`, then regenerate types.

## Outside actions

- Live migration push — check: `select version from supabase_migrations.schema_migrations where version = '20260930140000'` and `select jobname from cron.job where jobname = 'package-grace-enforcement'` — pending

## Notes

Ended free access covers through the local day it was ended, then the grace week runs (decided 2026-09-30 so ending it never pauses at once). The coverage reader `private.organization_access_coverage` is what P5b's banner must use; the access snapshot is SECURITY INVOKER and must not name `private` directly.

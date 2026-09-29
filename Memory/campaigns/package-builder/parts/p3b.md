# P3b — Remove the old package storage

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` · ADR 0003 decision 1
**Code:** `main`
**Done when:** No code or database function refers to the old package tables; `/get-started` and the prospect page still load; `npm run check` and the package tests pass

## Steps

- [x] Migration `20260930000000_remove_old_package_storage.sql` written and dry-run inside a rolled-back transaction
- [ ] Apply it (`npx supabase db push --linked`), regenerate `src/lib/database.types.ts`
- [ ] Code: `/get-started` + `/api/get-started` read public published editions and send `package_edition_id` + `billing_interval`; email-template restrictions use `package_id`; prospect page loses the "Change package" form (P10 rebuilds it); delete old Packages page, `/api/jafar/packages/**`, legacy-review route + `LegacyReconcileActions`, and the 410 stubs for package, package-version, feature/limit overrides
- [ ] `npm run check`, unit tests, browser check of `/get-started`, a prospect, an organization page, email templates

## Outside actions

- Apply migration 20260930000000 — check: `npx supabase migration list --linked` shows it remote, and `platform_packages` no longer exists — pending

## Notes

- Clearing free access would have switched off Raad LTD's email and chat allowance window, so the migration grants each active test organization open-ended free access until P5.
- `/get-started` shows no packages until Jafar publishes a public edition (P7); the only edition is the private test package.

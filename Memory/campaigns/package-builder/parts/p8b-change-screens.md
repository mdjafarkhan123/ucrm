# P8b — Package change screens

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § Assignment and changes
**Code:** `main`
**Done when:** the P8b done-check in `stages/3-customers.md`

## Steps

- [x] Migration `supabase/migrations/20261001100000_package_change_screens.sql`: Packages page counts current customers; each scheduled move lists what is over its limits now. Push, regenerate types
- [x] Billing route: preview (GET `billing/change-preview`), change, cancel scheduled change, use change credit; Zod + tests
- [x] Exceptions route `api/jafar/organizations/[id]/exceptions` (list, add, end early); tests
- [x] Switched-off `feature-overrides` / `limit-overrides` routes deleted; the four Communications panels (Email, Marketing, Website chat, Automation authority) now only show values and link to the Access tab
- [x] Billing tab: `BillingPackageSection.svelte` (current terms, scheduled change + cancel + over-limit warning, history), `PackageChangeDialog.svelte`, change credit block and dialogs in `BillingActionDialog.svelte`. Type check clean; **not yet opened in the browser**
- [x] Access tab: `AccessExceptionsSection.svelte` (features, limits with in-use, exceptions list, Add and End early dialogs) reading new `owner_organization_entitlements` via the exceptions route; browser-checked on Jaaroweb (add 60 seats, end early, 0-seat refusal)
- [ ] Browser check of the P8a done-checks through the screens

## Next

Change package dialog and Access tab are browser-checked (2026-09-30). Starter Check was restored from archive for that check.

1. Browser check of the done-checks in `stages/3-customers.md` through the screens: schedule a next-renewal move and cancel it on the Billing tab; on the Communications tab, confirm the four panels show values with the Access tab link (not yet opened in the browser).
2. Tidy two unused-variable lint errors from earlier work: `chargeLabel` in `BillingWorkspace.svelte`, `teamQuery` in `ActivityWorkspace.svelte`.
3. Close P8b per the Memory skill.

The database message for too few seats says "1 seats" (in `add_organization_package_exception`); fix the wording only if that function is changed anyway.

## Outside actions

- Migration push — check: `npx supabase migration list --linked` shows `20261001100000` remote — done 2026-09-30
- Migration push `20261001110000_owner_organization_entitlements.sql` (Access tab read) — same check for `20261001110000` — done 2026-09-30

## Notes

Package changes need no password (Jafar's list, 2026-09-30, covers only refund, void, correct payment, paid-through, free access).

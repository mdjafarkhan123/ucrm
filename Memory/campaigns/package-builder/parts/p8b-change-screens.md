# P8b — Package change screens

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § Assignment and changes
**Code:** `main`
**Done when:** the P8b done-check in `stages/3-customers.md`

## Steps

- [x] Migration `supabase/migrations/20261001100000_package_change_screens.sql`: Packages page counts current customers; each scheduled move lists what is over its limits now. Push, regenerate types
- [x] Billing route: preview (GET `billing/change-preview`), change, cancel scheduled change, use change credit; Zod + tests
- [x] Exceptions route `api/jafar/organizations/[id]/exceptions` (list, add, end early); tests
- [ ] Delete the switched-off `feature-overrides` / `limit-overrides` routes once nothing posts to them (Access tab and four Communications panels: Email, Marketing, Website chat allowances, Automation authority)
- [x] Billing tab: `BillingPackageSection.svelte` (current terms, scheduled change + cancel + over-limit warning, history), `PackageChangeDialog.svelte`, change credit block and dialogs in `BillingActionDialog.svelte`. Type check clean; **not yet opened in the browser**
- [ ] Access tab: features and limits from the new snapshot; exceptions list, add, end early
- [ ] Browser check of the P8a done-checks through the screens

## Next

1. Quick browser look at the Billing tab on Jaaroweb (`/jafar/organizations/4e99829a-dba2-4ea4-ae23-9fc16585f0f7?tab=billing`): open Change package, pick Starter Check, flip monthly/now, confirm the comparison and money read correctly. Do not confirm a change yet.
2. Build the Access tab: replace the old override table and three limit cards in `AccessWorkspace.svelte` with features and limits read from the new snapshot, plus an exceptions list (query key `jafarOrganizationExceptionsKey`, route `api/jafar/organizations/[id]/exceptions`) with Add and End early dialogs. Its package card's "returns with the new package tools" line should point to the Billing tab instead.
3. Point the four Communications panels off `limit-overrides`, then delete the two switched-off routes.
4. Browser check of the done-checks.

## Outside actions

- Migration push — check: `npx supabase migration list --linked` shows `20261001100000` remote — done 2026-09-30

## Notes

Package changes need no password (Jafar's list, 2026-09-30, covers only refund, void, correct payment, paid-through, free access).

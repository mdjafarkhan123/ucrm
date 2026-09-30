# P8b — Package change screens

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § Assignment and changes
**Code:** `main`
**Done when:** the P8b done-check in `stages/3-customers.md`

## Steps

- [x] Migration `supabase/migrations/20261001100000_package_change_screens.sql`: Packages page counts current customers; each scheduled move lists what is over its limits now. Push, regenerate types
- [x] Billing route: preview (GET `billing/change-preview`), change, cancel scheduled change, use change credit; Zod + tests
- [x] Exceptions route `api/jafar/organizations/[id]/exceptions` (list, add, end early); tests
- [ ] Delete the switched-off `feature-overrides` / `limit-overrides` routes once nothing posts to them (Access tab and four Communications panels: Email, Marketing, Website chat allowances, Automation authority)
- [ ] Billing tab: Package block (current terms, scheduled change + cancel + over-limit warning, terms history), Change package dialog, change credit shown and usable
- [ ] Access tab: features and limits from the new snapshot; exceptions list, add, end early
- [ ] Browser check of the P8a done-checks through the screens

## Next

Build the Billing tab Package block and Change package dialog (`src/lib/components/jafar/organization/`).

## Outside actions

- Migration push — check: `npx supabase migration list --linked` shows `20261001100000` remote — done 2026-09-30

## Notes

Package changes need no password (Jafar's list, 2026-09-30, covers only refund, void, correct payment, paid-through, free access).

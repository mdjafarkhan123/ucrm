# A4 — Stage editor

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1
**Code:** `main`
**Done when:** A stage tied to Website shows only to a client whose package includes Website

## Steps

- [x] Migration `supabase/migrations/20261007110000_setup_stage_editor.sql` written (draft/save/publish/discard, per-client service filter, onboarding list per-client totals)
- [ ] Apply migration to the dev database, regenerate `src/lib/database.types.ts`
- [ ] Wizard filter: `readOrganizationSetupCatalogue` in `src/lib/server/setup/catalogue.ts`, used by setup routes, reminders, support start; empty stages hidden in `buildSetupCatalogue`
- [ ] Onboarding list: per-client `sections_total`/`facts_total` replace `setup_size`
- [ ] Jafar API `/api/jafar/setup` (GET, POST start), `/draft` (PATCH save, DELETE discard), `/draft/publish`
- [ ] Page `/jafar/setup` + nav item "Client setup"; mirrors the package builder (RecordFormLayout, rail, save bar)
- [ ] Tests, checks, browser check of done-check, commit

## Next

Apply the migration (see Outside actions), then the wizard filter step.

## Outside actions

- Apply migration `20261007110000_setup_stage_editor` to dev Supabase — check: `list_migrations` shows version `20261007110000` — pending

## Notes

- Rules decided: a stage holding built-in questions can't be removed or tied to a service; a stage with no questions is saved but hidden from clients until A5 adds questions; new stage keys never reuse an old version's key.

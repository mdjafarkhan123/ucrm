# A5e — Add-another lists

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1;
blueprint `docs/client-onboarding-setup-content-blueprint.md` "Structured" rows
**Code:** `main`
**Done when:** A client adds, edits and removes rows; they save and resume

## Steps

- [ ] Migration `20261009110000_setup_list_answers` written; apply to dev. Outcome check: `select 1 from
  supabase_migrations.schema_migrations where version = '20261009110000'` and column `setup_items.list_fields` exists
- [ ] Answer rules + tests (`$lib/setup/answer-values` or own module), catalogue kind `list`
- [ ] Editor: list question with boxes (name, type, required, choices), row limit, starters
- [ ] Client wizard: rows as numbered cards, Add another / Remove (MOJ "Add another" pattern); 1-row limit shows a plain form
- [ ] Checks, browser check in the editor, commit

## Next

Run the outcome check, then apply the migration if it has not landed; regenerate database types.

## Notes

Decided with Jafar 2026-10-04:
- Row boxes may be short/long text, phone, email, web link, date, number, money, yes/no, pick one, and photo or file (one file per box).
- The editor offers starters — Person, Address, Service, Link + note — which fill in named boxes Jafar can still change; or a blank list.
- Stored as a JSON list of rows; each row has its own id so A5f can pick rows without copying them.

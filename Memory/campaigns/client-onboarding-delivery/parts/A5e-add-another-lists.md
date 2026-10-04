# A5e — Add-another lists

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1;
blueprint `docs/client-onboarding-setup-content-blueprint.md` "Structured" rows
**Code:** `main`
**Done when:** A client adds, edits and removes rows; they save and resume

## Steps

- [x] Migration `20261009110000_setup_list_answers` applied to dev; rules spot-checked in SQL; types updated. Outcome check: `select 1 from
  supabase_migrations.schema_migrations where version = '20261009110000'` and column `setup_items.list_fields` exists
- [x] Answer rules + tests (`$lib/setup/lists.ts`), catalogue kind `list`, file check on save, uploads into a file box
- [x] Editor: `SetupListBoxes.svelte` — boxes (name, type, required, choices, file kinds), row limit, starters; Zod + tests
- [x] Client wizard: `SetupListField.svelte` — numbered cards, Add another / Remove; 1-row limit shows a plain form (not yet seen in a browser)
- [ ] Checks, browser check in the editor, commit

## Next

Browser check on `/jafar/setup/business` (start a draft): add a list question from the Service starter, save, reload, discard the draft. Then a client-side look only if a draft-free way exists — never publish test questions.

## Notes

Decided with Jafar 2026-10-04:
- Row boxes may be short/long text, phone, email, web link, date, number, money, yes/no, pick one, and photo or file (one file per box).
- The editor offers starters — Person, Address, Service, Link + note — which fill in named boxes Jafar can still change; or a blank list.
- Stored as a JSON list of rows; each row has its own id so A5f can pick rows without copying them.

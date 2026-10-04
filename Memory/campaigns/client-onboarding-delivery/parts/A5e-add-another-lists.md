# A5e — Add-another lists

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1;
blueprint `docs/client-onboarding-setup-content-blueprint.md` "Structured" rows
**Code:** `main`
**Done when:** A client adds, edits and removes rows; they save and resume

## Steps

- [x] Migration `20261009110000_setup_list_answers` applied to dev; rules spot-checked in SQL; types updated. Outcome check: `select 1 from
  supabase_migrations.schema_migrations where version = '20261009110000'` and column `setup_items.list_fields` exists
- [x] Answer rules + tests (`$lib/setup/lists.ts`), catalogue kind `list`, file check on save, uploads into a file box
- [ ] Editor: list question with boxes (name, type, required, choices), row limit, starters
- [x] Client wizard: `SetupListField.svelte` — numbered cards, Add another / Remove; 1-row limit shows a plain form (not yet seen in a browser)
- [ ] Checks, browser check in the editor, commit

## Next

Editor: `src/lib/jafar/setup-editor.ts` (svelte-check error at the kind labels), Zod `setup-editor.schema.ts` (list_fields, max_rows, box keys like choiceValues), `SetupQuestionList.svelte` box editor + starters from `SETUP_LIST_STARTERS`.

## Notes

Decided with Jafar 2026-10-04:
- Row boxes may be short/long text, phone, email, web link, date, number, money, yes/no, pick one, and photo or file (one file per box).
- The editor offers starters — Person, Address, Service, Link + note — which fill in named boxes Jafar can still change; or a blank list.
- Stored as a JSON list of rows; each row has its own id so A5f can pick rows without copying them.

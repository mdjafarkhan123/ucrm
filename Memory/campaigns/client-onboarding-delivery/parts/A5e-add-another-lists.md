# A5e — Add-another lists

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1;
blueprint `docs/client-onboarding-setup-content-blueprint.md` "Structured" rows
**Code:** `main`
**Done when:** A client adds, edits and removes rows; they save and resume

## Steps

- [ ] Migration: new question type "list" with its boxes and row limit; carried through catalogue, draft copy, stage save; file boxes link their Files like file answers
- [ ] Answer rules + tests (`$lib/setup/answer-values` or own module), catalogue kind `list`
- [ ] Editor: list question with boxes (name, type, required, choices), row limit, starters
- [ ] Client wizard: rows as numbered cards, Add another / Remove (MOJ "Add another" pattern); 1-row limit shows a plain form
- [ ] Checks, browser check in the editor, commit

## Next

Write the migration (copy the latest versions of the functions from `20261009100000_setup_file_answers.sql`).

## Notes

Decided with Jafar 2026-10-04:
- Row boxes may be short/long text, phone, email, web link, date, number, money, yes/no, pick one, and photo or file (one file per box).
- The editor offers starters — Person, Address, Service, Link + note — which fill in named boxes Jafar can still change; or a blank list.
- Stored as a JSON list of rows; each row has its own id so A5f can pick rows without copying them.

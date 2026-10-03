# A5d — More answer types

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1;
answer column of `docs/client-onboarding-setup-content-blueprint.md`
**Code:** `main`
**Done when:** each type saves, reloads and refuses a bad value

## Decisions (Google Forms pattern)

- New kinds: `multi_choice` (tick several), `yes_no_unsure`, `url`, `number`, `money`, `percentage`,
  `distance` (miles/km), `duration` (minutes/hours/days), `colours`.
- Pick one and tick several get an optional "Other" box (`allow_other`); the client's words are stored in place
  of a choice, like built-in trade/language. Tick several may cap ticks (`max_choices`).
- Compound answers are JSON like hours: tick several = array; money = amount + currency; distance/time =
  amount + unit; colours = array of hex codes. Number and percentage are JSON numbers.

## Steps

- [x] Migration `20261009090000_setup_more_answer_types` applied to dev. Outcome check: `select 1 from
  supabase_migrations.schema_migrations where version = '20261009090000'` and column
  `setup_items.allow_other` exists
- [ ] Catalogue rules + validation + unit tests
- [ ] Client wizard fields
- [ ] Editor: type picker, Other toggle, up-to-N, show-if sources
- [ ] svelte-check, unit tests, browser check, commit

## Next

Apply the migration (check its outcome first), then the catalogue rules in `src/lib/setup/catalogue.ts`.

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

- [x] Migration `20261009090000_setup_more_answer_types` applied to dev; rules proven in SQL (rolled back)
- [x] Rules + tests: `src/lib/setup/answer-values.ts`, `catalogue.ts`, editor Zod schema, `setup-editor.ts`
- [x] Client fields: `SetupChoicesField`, `SetupAmountField` (number, %, money, distance, time; keeps typed
  text; decimal comma), `SetupColoursField`, wired in `SetupField`; section GET sends `country`, `currency`
- [x] Editor: new types in the picker, "Add Other" switch, "Most ticks allowed"
- [x] svelte-check 0 errors; setup unit tests green; committed
- [ ] Browser check — never done, nothing seen on screen yet

## Next

Browser check on dev without publishing (keys are never reused): open `/jafar/setup`, edit a stage in the
existing draft, add one question of each new type (tick several with Other and a limit of 2), save, reload,
check each saves; then discard those test questions (remove them and save). Look hard at
`SetupAmountField`: the currency sign sits over the box; check it lines up and does not cover the label. The
client-side fields can only be seen after a publish, so their live look joins A5's hands-on publish with
Jafar. Then close A5d (mark Done in `stages/A-groundwork.md`, delete this note, point NOW.md at A5c).

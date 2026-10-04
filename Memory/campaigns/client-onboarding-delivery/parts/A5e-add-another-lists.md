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
- [x] Editor browser-checked on dev: Service starter + photo box saved as 4 boxes with keys, reloads, starters hidden once saved
- [ ] Client box tests `src/lib/components/setup/SetupListField.svelte.spec.ts` (browser tests, `npx vitest run --project client <file>`): 3 pass, the first is `it.skip`
- [ ] Discard the dev draft (version 2) on `/jafar/setup` — it holds the test question "Add every service you offer"; never publish it
- [ ] Mark A5e done (roadmap, NOW.md, delete this note)

## Next

Un-skip the first test in `SetupListField.svelte.spec.ts` and make it pass. It fails at `toHaveFocus` after
"Add another": `add()` in `SetupListField.svelte` focuses the new entry's first box via
`requestAnimationFrame` + `#<id>-<rowId> .setup-list__boxes :is(input, textarea, button)` (just changed from a
selector that hit the Remove button — that fix is committed). Find why focus still misses (maybe the Input's
real `<input>` id/wrapper, or timing — try `await tick()` instead), then run the client test file, the setup
unit tests and `npm run check` (needs `NODE_OPTIONS=--max-old-space-size=8192`), commit, discard the dev draft.

## Notes

Decided with Jafar 2026-10-04:
- Row boxes may be short/long text, phone, email, web link, date, number, money, yes/no, pick one, and photo or file (one file per box).
- The editor offers starters — Person, Address, Service, Link + note — which fill in named boxes Jafar can still change; or a blank list.
- Stored as a JSON list of rows; each row has its own id so A5f can pick rows without copying them.

# A5f — Pick from an earlier list

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1;
blueprint "Ordered selection"
**Code:** `main`
**Done when:** Top-services choice lists only entered services, in the client's order; a removed service drops out

## Steps

- [x] Migration `20261010090000_setup_pick_answers` applied to dev; rules proven in SQL (rolled back)
- [x] Answer rules (`src/lib/setup/picks.ts`, catalogue), server check + tidy-up on list save, "Mark as done"
      asks for the fewest picks; client pick box `SetupPickField.svelte` with Move up/down; unit + API tests
- [ ] Editor: `setup-editor.ts` DraftItem/payload (`pick_from` as `{fact_key}` or `{item: n}` like show-if,
      `min_choices`, `max_choices`, `ordered`), Zod in `setup-editor.schema.ts`, settings box in
      `SetupQuestionList.svelte` (choose an earlier list question, fewest, most, "Client puts them in order")
- [ ] svelte-check, tests, browser-check the editor (save a pick, discard the draft — never publish)

## Outside actions

- Migration applied — check: `supabase_migrations.schema_migrations` has `20261010090000` — done

## Notes

- Fewer picks than the minimum still autosave (no error while ticking); only "Mark as done" refuses.
- The pick names each row by the list's first box.

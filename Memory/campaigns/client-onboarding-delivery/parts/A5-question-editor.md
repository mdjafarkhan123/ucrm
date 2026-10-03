# A5 — Question editor

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1
**Code:** `main`
**Done when:** Jafar adds a question, publishes, and a client mid-setup sees and answers it; a built-in question
offers no Delete; a stage tied to Website shows only to a client whose package includes Website

## Steps

- [x] Migration `supabase/migrations/20261008090000_setup_question_editor.sql` written (yes/no + date types, answered-question index, editor `answered` list, `owner_save_setup_draft_stage_items`, publish re-checks answer type)
- [ ] Apply it to dev
- [ ] Catalogue: `yes_no` → radio Yes/No choice, `date` → CalendarPicker in `SetupField`; date validation
- [ ] API `PATCH /api/jafar/setup/draft/stages/[stage]` + Zod (option values made from labels)
- [ ] Page `/jafar/setup/[stage]` question list (Google Forms/Tally-style cards); "Edit questions" link on each saved stage; publish review lists question changes
- [ ] Unit tests, svelte-check, browser check, commit
- [ ] Client-side proof (see Done when) — publish only a real question Jafar wants; stage and question keys are never reused

## Next

Apply the migration to dev (outside action below), then the catalogue step.

## Outside actions

- Apply migration `20261008090000_setup_question_editor` to dev — check: `select 1 from pg_proc where proname = 'owner_save_setup_draft_stage_items'` — pending

## Notes

- Moving a built-in question to a different stage is not in this part; only reordering within its stage.

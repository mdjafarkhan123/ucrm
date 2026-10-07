# A2 — Settings home

**Campaign:** jafar-business-management · **Plan:** `docs/jafar-business-management-behavior-contract.md` § Settings across `/jafar`
**Code:** `main`
**Done when:** Jafar searches "sender", opens that setting, saves it — on desktop and phone width

## Steps

- [x] Migration: owner settings save one section at a time (null keeps the saved value)
- [ ] PATCH `/api/jafar/settings` accepts a partial body; spec updated
- [ ] Settings home: six groups, search, needs-attention marks (reuse `SettingsDestinationCard`, `SectionBlock`)
- [ ] Focused pages: sender & reply-to, alert recipients, payment instructions, privacy policy
- [ ] Sidebar: System emails, Email templates, Email safety leave Platform Operations (now in Settings)
- [ ] Browser check desktop + phone width; commit

## Next

Change the PATCH route to accept a partial body and pass null for absent fields.

## Outside actions

- Apply `supabase/migrations/20261106090000_owner_settings_partial_update.sql` to remote — check: `select prosrc like '%coalesce(new_sender_display_name%' from pg_proc where proname = 'update_owner_settings'` returns true — pending

## Notes

Jafar, 2026-10-07: show all six groups now (empty ones carry one quiet line saying what arrives there and
when); move System emails, Email templates and Email safety out of the sidebar into Settings.
Support messenger settings stay in the Support page dialog — not listed by the plan.

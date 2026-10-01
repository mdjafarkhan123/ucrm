# A1 — Add custom stages in Settings

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` § First-release board, "Revision 3 adds section-bound custom follow-up stages"
**Code:** `main`
**Done when:** The owner adds "Waiting on customer" under Quotes and it appears as an empty column for everyone; a 26th stage and a repeated name in the same section are refused with a clear message; a sales login cannot change stages

## Steps

- [x] Design: stages saved with the rest of Settings → Pipeline under the one Save button and revision
- [ ] Database: `pipeline_custom_stages` table and `save_pipeline_settings` command (replaces `save_pipeline_presentation`)
- [ ] API: Settings → Pipeline read and save carry the stage list; board summary returns the stages
- [ ] Settings page: stage list per section with add, rename, move up/down
- [ ] Board: custom stages drawn as empty columns in their saved place
- [ ] Checks: unit tests, pgTAP, `npm run check`, browser walk of the done-check with owner and sales logins

## Next

Apply the migration (see Outside actions), then build the API, Settings page, and board columns.

## Outside actions

- Apply migration `20261001210000_pipeline_custom_stages.sql` with `supabase db push --linked` — check: `supabase migration list --linked` shows 20261001210000 on the remote side, and `public.save_pipeline_settings` exists — pending

## Notes

- A custom stage is stored with the protected stage it sits after, so it can sit between protected stages
  (Jobber's rule) while the first stage of each section stays first.
- No card can be in a custom stage until A2, so the board draws these columns without asking the server for
  cards, and the board's card-reading functions are untouched. A2 owns that read-path change and its
  performance review.
- Switching off or deleting a saved stage is A3. In A1 a saved stage can only be renamed or moved.

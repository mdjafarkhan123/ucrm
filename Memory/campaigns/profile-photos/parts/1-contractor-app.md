# 1 — Contractor app photos

**Campaign:** profile-photos · **Plan:** approved behavior in `NOW.md` (no plan document yet)
**Code:** worktree `../Ucrm-profile-photos`, branch `profile-photos` (work-in-progress commit on it)
**Done when:** On `main`; a staff member adds and removes a photo in the browser and teammates see it

## Steps

- [x] Database: photo column, server-only writes, `set_profile_photo` — applied to the dev database
- [x] Upload and remove route, photo view route, photo cleaning (crop, shrink, strip location data) with tests
- [x] Pop-up to choose, drag, zoom and save; account menu item; Settings "Change photo"; top bar shows photo
- [x] Browser: upload, top bar, Settings, Team list all show the photo
- [ ] Fix the bug below
- [ ] Browser: Remove photo; recheck the pop-up's button row and its keyboard focus after the last edits
- [ ] Merge the branch into `main`, run the checks there, remove the worktree, release the claim

## Next

Fix: on Settings (`src/routes/(app)/settings/+page.svelte`), a real mouse click on "Change photo" right
after the page loads does not open the pop-up (`src/lib/components/profile/ProfilePhotoDialog.svelte`); a
click sent from code opens it every time, and the account-menu route always works. Also seen once: neither
the X nor Escape closed it after the page had live-reloaded — retest from a clean reload before chasing it.

## Outside actions

- Database changes on the dev database — check: `supabase_migrations.schema_migrations` has versions
  `20261007100121` (profile_photos) and `20261007100205` — done. Their files are only on the branch until
  merged; do not reapply.

## Notes

- The Raad LTD owner (Jafar Khan) has a test photo saved; remove it during the Remove check.
- The worktree needs a `.env` link to the main folder's, and `svelte-check` needs
  `NODE_OPTIONS=--max-old-space-size=8192`.

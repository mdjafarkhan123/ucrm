# 2 — `/jafar` panel photos

**Campaign:** profile-photos · **Plan:** no plan document yet — Jafar and each panel teammate change only their own photo; any signed-in `/jafar` person sees them; contractor staff photos show in a client's Team tab.
**Code:** worktree `../Ucrm-photos`, branch `profile-photos-p2`
**Done when:** On `main`; Jafar and a teammate add a photo in `/jafar` and see it in the menu and team list

## Steps

- [x] Database: photo columns on `platform_team_members` and `platform_owner_settings`, plus `set_platform_team_member_photo` / `set_platform_owner_photo`
- [x] Server: `/api/jafar/account/photo` (POST/DELETE, own photo) and `/api/jafar/photos/[who]` (GET); open both to every signed-in person in `team-access.ts`
- [x] Contractor staff photo route under `/api/jafar/organizations/*/team/*/photo`; team API returns it
- [x] Shell: photo in the `/jafar` top bar and menu; `ProfilePhotoDialog` takes the endpoint
- [x] Avatars with photos in `/jafar` Settings → Team and a client's Team tab
- [ ] Tests, checks, browser check, merge to `main`

## Next

Code is committed on the branch, with tests passing. Next: check it in the browser from the worktree's dev server on port 5180, as Jafar (`/jafar`) and as Sam Seller: add a photo, see it in the top bar and in Settings → Team, then remove it. Then merge into `main`.

## Outside actions

- Migration `jafar_profile_photos` — check: `supabase_migrations.schema_migrations` version `20261007122323` — done

## Notes

Jafar and his teammates are not Supabase users (ADR 0008), so Part 1's `profiles` column and `/api/profile/photo` cannot serve them.

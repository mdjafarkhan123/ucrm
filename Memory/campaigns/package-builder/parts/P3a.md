# P3a — New storage and the access switch

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § Build checks · ADR 0003 decisions 1, 2, 4, 5
**Code:** branch `wip/package-builder-p3a` (no worktree; switch the main folder to it). Merge into `main` when the part passes.
**Done when:** every test login sees the same screens as before; the organization page shows each test organization's new edition; a test proves that removing a capability from an edition makes its screens answer "not part of your plan".

## Steps

- [x] Migration `20260929230000` (new storage, test package, agreements, all checks switched) — applied
- [x] Fix migration `20260929233000`: the allowance resolver moved to `public` because members cannot use the `private` schema — applied
- [x] Resolver, its tests, and the "capability removed → not part of your current plan" test (`src/lib/server/access/permission.spec.ts`)
- [x] Jafar organization page shows the edition; "Change package" and "Assign version" removed
- [x] Old package, exception, free-access, payment, and activation writes answer 410 through `src/lib/server/packages/rebuilding.ts`
- [x] Database types regenerated; type check 0 errors; all unit tests pass
- [ ] Browser check: six test logins and the Jafar organization page (Overview + Access & limits tabs) for all four organizations
- [ ] Merge the branch into `main`; commit

## Next

`git switch wip/package-builder-p3a`, start `npm run dev`, then do the browser check. After the fix, the already-signed-in Raad session got 200 from Pipeline, Marketing, and the email-template library; nothing else is checked yet. Test logins are in `CLAUDE.md`.

## Outside actions

- Both migrations applied 2026-09-29 — check: `select version from supabase_migrations.schema_migrations where version in ('20260929230000','20260929233000')` (expect 2) and `select count(*) from public.organization_package_agreements` (expect 4) — done

## Notes

- A SECURITY INVOKER function that members call must not name anything in `private` in its body. Unit tests can't catch this; only a real login does.
- Raad's limits after the switch match before: 50 seats, 5 chat widgets, 20 chats, unlimited marketing email, automations on. The other three organizations now have the same access.
- The test edition leaves out only missed-call text-back. Automation safety controls live in `platform_automation_safety_limits`, all unlimited, until P14.
- Old tables stay, unread, until P3b. History clean-up is in P3b. Free access still reads the old events until P5.
- Lint errors in `AccessWorkspace.svelte` and `ActivityWorkspace.svelte` were already there before this part.

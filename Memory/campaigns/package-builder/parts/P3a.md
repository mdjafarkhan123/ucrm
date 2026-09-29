# P3a — New storage and the access switch

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § Build checks · ADR 0003 decisions 1, 2, 4, 5
**Code:** branch `wip/package-builder-p3a` (one WIP commit, no worktree). Merge into `main` when the part passes.
**Done when:** every test login sees the same screens as before; the organization page shows each test organization's new edition; a test proves that removing a capability from an edition makes its screens answer "not part of your plan".

## Steps

- [x] Migration written on the branch: `supabase/migrations/20260929230000_package_editions_and_agreements.sql` (new tables, capability seed, test package, agreements, all limit functions, snapshot, directory). **Not applied.**
- [x] `src/lib/server/access/effective.ts` rewritten on the branch: `package` is now the agreement and edition (or null)
- [ ] Fix the remaining type errors: `effective.spec.ts` (old `current_key`/`effective_key` fixtures; rewrite fixtures to the new snapshot shape), the two email-template routes (`access.package?.slug`), `src/lib/components/jafar/organization/types.ts`, `OverviewWorkspace.svelte`, `AccessWorkspace.svelte`; check `buildAutomationLimits` in `src/lib/server/access/automation.ts` accepts source `'platform'`
- [ ] Add the "capability removed → not part of your plan" unit test
- [ ] Old write routes answer 410 "being rebuilt": `api/jafar/organizations/[organizationId]/` package, package-version, feature-overrides, limit-overrides, free-access (POST), commercial (payment kinds only; keep timezone), `api/jafar/packages/*` writes, prospect confirm-payment, provision, correct-package; marketing-allowance route reads `organization_package_exceptions`
- [ ] `npx supabase db push --linked --dry-run`, then apply; run the snapshot and limit functions for Raad as a check
- [ ] Browser check with the six test logins and the Jafar organization page; merge to `main`; commit

## Next

`git switch wip/package-builder-p3a`, then run `NODE_OPTIONS=--max-old-space-size=8192 npx svelte-check --tsconfig ./tsconfig.json --output machine | grep ERROR` (plain `npm run check` runs out of memory) and fix the errors listed in Steps.

## Outside actions

- Apply migration `20260929230000` to the remote database — check: `select 1 from supabase_migrations.schema_migrations where version = '20260929230000'` and `select count(*) from public.organization_package_agreements` (expect 4) — pending

## Notes

- The test edition copies Raad's effective access on 2026-09-29: every capability except missed-call text-back; seats 50, chat widgets 5, accepted chats 20, operational, essential, and marketing email unlimited, active automations unlimited. Monthly $249.
- Automation safety controls moved to `platform_automation_safety_limits`, seeded unlimited (today's test behaviour); P14 sets the agreed values.
- Old tables stay, unread, until P3b. History clean-up moved to P3b: old payment events are referenced by email and chat allowance periods and the commercial-state row.
- Free access is still read from the old events until P5.

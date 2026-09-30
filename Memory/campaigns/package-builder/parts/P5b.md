# P5b — Contractor banner and paused screen

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § Offsite payment and coverage (who sees the banner and the paused screen)
**Code:** `main`
**Done when:** in the browser, a test organization in grace shows the banner to owner and not to field; a paused one shows each role its screen; every test login still sees the same screens when active

## Steps

- [x] Migration `20260930160000_contractor_account_standing.sql` (applied to the LOCAL database only) and test `contractor_account_standing.sql` (8 pass locally)
- [x] `src/lib/account/standing.ts`, `components/layout/AccountGraceBanner.svelte`, `components/layout/PausedAccountScreen.svelte` written; not yet wired in or checked with the Svelte autofixer
- [ ] Push the migration live, regenerate types (`npm run db:types`, then prettier on the file)
- [ ] Wire in (below), autofixer, `npm run check` (needs `NODE_OPTIONS=--max-old-space-size=8192`), browser check, commit

## Next

1. `npx supabase db push --linked` (dry-run first).
2. `src/routes/(app)/+layout.server.ts`: call `event.locals.supabase.rpc('contractor_account_standing')` in parallel with `getOrganizationContext`, before the early `if (!context) return` (a paused organization gives no context), and return `standing` in both branches.
3. `AppShell.svelte`: add an optional `notice` snippet rendered between `Topbar` and `.app-shell__main`.
4. `(app)/+layout.svelte`: when `data.standing?.state === 'paused'` render only `PausedAccountScreen`; add `enabled: !paused` to every nav probe query and skip the idle page warming; when `state === 'grace'` pass `AccountGraceBanner` with `last_access_day` as the shell's `notice`.
5. Browser check: move a test organization into grace, then paused (adjust paid-through in Jafar's Billing tab), then restore it.

## Outside actions

- Live migration push — check: `select version from supabase_migrations.schema_migrations where version = '20260930160000'` — pending

# E2 — Provider waits

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 5 (Jafar's choices of 2026-10-05, E2)
**Code:** `main`
**Done when:** A provider wait never shows Uplift as late or done

## Steps

- [x] Jafar's choices recorded in plan §5
- [x] Migration `20261031090000_setup_provider_waits.sql` written (table, `owner_set_setup_provider_wait`, list counts)
- [x] Apply migration to dev
- [x] Regenerate types
- [x] `$lib/setup/provider-waits.ts` (keys, labels, provider words) + spec
- [x] Jafar API `POST/…/setup/provider-waits` (Zod) + "You need to do something" email
- [x] Jafar's Setup tab panel; Onboarding list tag and `provider_action`
- [x] Client "Waiting on others" card under the tracker on `/setup`
- [ ] Checks, browser check on Raad LTD, commit

## Next

Browser check: no dev client's package has Google/texting/website, so put one wait on Raad LTD by SQL
(`insert into organization_setup_provider_waits … 'google_profile','action_needed'`), check the client's
`/setup` card and the "You need to do something" email in the outbox, Jafar's Setup tab panel (shows started
waits outside the package so they can be cleared) and the Onboarding tag; then clear it from the panel.
Database rules were already tested in a self-undoing block (all passed).

## Outside actions

- Apply migration to dev — check: `select 1 from supabase_migrations.schema_migrations where version = '20261031090000'` — done (applied via MCP, version renumbered to match; function bodies' md5 match the file)

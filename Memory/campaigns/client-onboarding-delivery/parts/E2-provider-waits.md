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

Finish the browser check, then close E2. Already seen working in the browser: Jafar's panel on Raad LTD's Setup
tab, the client's "Waiting on others" card on `/setup` (link `/setup#outside-waits` jumps to it; a scroll margin
was added after the title sat under the top edge — recheck it), the dialog asking for a note, and the plain
"package does not include that service" refusal. Still to check: choosing "Not started" in the dialog clears
the wait (the last try did not seem to change the dropdown — check if it is a real bug), and the Onboarding
list's "outside waits" tag. No dev client's package has Google, texting or website, so put a test wait on Raad
by SQL (`updated_by_email = 'browser-check@example.com'`) and delete it afterwards. Then mark E2 done.
Database rules were all tested in a block that undid itself.

## Outside actions

- Apply migration to dev — check: `select 1 from supabase_migrations.schema_migrations where version = '20261031090000'` — done (applied via MCP, version renumbered to match; function bodies' md5 match the file)

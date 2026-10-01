# D2 — Live replies and unread badges

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 7
**Code:** `main`
**Done when:** Reply appears without refresh; badge clears on read

## Steps

- [x] Design (performance-review): Realtime Broadcast from the database, ids-only pings, re-read through the API (same as Website Chat)
- [ ] Apply migration `20261002235000_support_live_and_unread.sql`
- [ ] Member side: live subscription + unread badge on Chat with Uplift + mark read when seen
- [ ] Jafar side: owner grant route, live subscription in `/jafar` layout, Support nav count, unread rows, mark read
- [ ] Tests, checks, browser check both sides

## Next

Apply the migration from a scratch copy that also holds pipeline D2's `20261002233000` file (it is on the
remote ledger but not yet on `main`), then build the member side.

## Outside actions

- Push migration 20261002235000 — check: version `20261002235000` in `supabase_migrations.schema_migrations` — pending

## Notes

- Jafar chose "follow the industry pattern": instant on both sides (Intercom/Help Scout/Zendesk), 30-second
  checks only while the live connection is down.
- The `/jafar` login is not a Supabase sign-in, so each owner session gets a secret short-lived channel name
  (`platform_support_realtime_grants`), like Website Chat visitor grants.

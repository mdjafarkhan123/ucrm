# D2 — Live replies and unread badges

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 7
**Code:** `main`
**Done when:** Reply appears without refresh; badge clears on read

## Steps

- [x] Design (performance-review): Realtime Broadcast from the database, ids-only pings, re-read through the API (same as Website Chat)
- [x] Apply migration `20261002235000_support_live_and_unread.sql`
- [x] Member side: live subscription + unread badge on Chat with Uplift + mark read when seen
- [x] Jafar side: owner grant route, live subscription in `/jafar` layout, Support nav count, unread rows, mark read
- [x] Tests and checks (route specs, svelte-check, lint)
- [ ] Browser check both sides

## Next

Browser check: sign in as the contractor owner and open `/jafar/support` in a second window; send, reply,
watch both update without refresh; badge on Chat with Uplift and the Support menu clears on read.

## Outside actions

- Migrations 20261002235000 and 20261002235500 — applied and SQL-tested

## Notes

- Jafar chose "follow the industry pattern": instant on both sides (Intercom/Help Scout/Zendesk), 30-second
  checks only while the live connection is down.
- The `/jafar` login is not a Supabase sign-in, so each owner session gets a secret short-lived channel name
  (`platform_support_realtime_grants`), like Website Chat visitor grants.

# D5a — Solved, reopen, Uplift starts a chat

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 7 "Follow-up"
**Code:** `main`
**Done when:** A solved chat reopens when the member writes and keeps its history; a chat Jafar starts reaches the
chosen member.

## Steps

- [ ] Database change `20261006160000_support_solved_and_uplift_starts` applied, types regenerated
- [ ] Server: status route, Uplift start route, inbox status filter, status in member reads
- [ ] Screens: Solved/Reopen in Support Inbox, status filter, Solved mark in messenger list, New chat +
      Message this business, Chat with Uplift on the paused screen
- [ ] Checks, tests, browser run both sides

## Next

Apply the migration through Supabase MCP `apply_migration` (the CLI cannot reach the database from here).

## Outside actions

- Apply migration `20261006160000_support_solved_and_uplift_starts` — check: `select version from
  supabase_migrations.schema_migrations where version like '20261006160000%'` or column
  `support_threads.status` exists

## Notes

Writing reopens quietly, with no grey line; Uplift's own Solved/Reopen leave one. An Uplift-started chat belongs to
the chosen member (`started_by_user_id`), with `opened_by = 'uplift'`.

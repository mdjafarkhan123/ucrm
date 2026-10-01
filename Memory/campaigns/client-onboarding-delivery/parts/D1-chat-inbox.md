# D1 — Chat with Uplift + Support Inbox

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 7
**Code:** `main`
**Done when:** Contractor sends, Jafar replies, both see it; customer inbox unaffected

## Steps

- [x] Performance design: the chat button asks the server nothing until hovered; one thread per member
- [x] Migration file written: `supabase/migrations/20261002220000_support_messenger.sql`
- [ ] Apply the migration and regenerate `src/lib/database.types.ts` (`npm run db:types`)
- [ ] Contractor routes: `GET /api/support/thread`, `POST /api/support/messages`
- [ ] Jafar routes under `/api/jafar/support/` (threads, one thread, reply, settings)
- [ ] Shared thread view + `Chat with Uplift` button in `src/routes/(app)/+layout.svelte`
- [ ] `/jafar/support` inbox page, sidebar entry, responder name + hours setting
- [ ] Chat mentioned in the setup welcome's "Stuck on something?" line
- [ ] Tests, browser check both sides, performance verification

## Next

Apply the migration (dry-run first), then build the routes.

## Outside actions

- `supabase db push --linked` of migration `20261002220000` — check: `supabase migration list` shows
  `20261002220000` on the remote side, and table `public.support_threads` exists — pending

## Notes

- D1 shows each member only their own thread. D3 widens the one policy on `support_threads`.
- No live updates yet (D2): an open chat re-checks every 15 seconds; closed, it asks nothing.
- Jafar must set his responder name in the inbox's Support settings before the first reply is allowed.

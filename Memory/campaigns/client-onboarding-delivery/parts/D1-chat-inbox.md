# D1 — Chat with Uplift + Support Inbox

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 7
**Code:** `main`
**Done when:** Contractor sends, Jafar replies, both see it; customer inbox unaffected

## Steps

- [x] Performance design: the chat button asks the server nothing until hovered; one thread per member
- [x] Migration `20261002220000_support_messenger.sql` applied; types regenerated
- [x] Contractor routes `/api/support/thread`, `/api/support/messages`; Jafar routes under `/api/jafar/support/`
- [x] `SupportConversation`, `SupportMessenger` (in `src/routes/(app)/+layout.svelte`), `SupportSettingsDialog`
- [x] `/jafar/support` page + sidebar entry; setup welcome mentions the chat
- [x] Route tests (26 pass); database rules tested by SQL in a rolled-back transaction; `npm run check` 0 errors
- [ ] Browser check both sides (desktop + phone width): owner sends, Jafar sets his name, replies, owner sees it
- [ ] Performance verification branch (`performance-review` verify.md)
- [ ] Mark D1 done in `stages/D-support.md`, delete this note

## Next

Browser check. Chrome extension was not connected last session; Playwright Chromium is installed
(`~/.cache/ms-playwright`) and the dev server runs on `127.0.0.1:5173`. Sign in as the contractor owner
(CLAUDE.md logins), open Chat with Uplift, send; then `/jafar/login`, Support, set the responder name,
reply; back on the contractor side the reply should appear within 15 seconds.

## Outside actions

- `supabase db push --linked` of `20261002220000` — done (dry-run then push; tables exist)

## Notes

- D1 shows each member only their own thread. D3 widens the one policy on `support_threads`.
- No live updates yet (D2): an open chat re-checks every 15 seconds; closed, it asks nothing.
- A reply is refused until Jafar sets his responder name in Support settings (by design).
- The svelte autofixer reports "unused CSS" / "invalid identifier" on these files because it does not run
  the SCSS preprocessor; `npm run check` is the real check and is clean.
- `npm run check` needs `NODE_OPTIONS=--max-old-space-size=8192` and takes over 10 minutes.

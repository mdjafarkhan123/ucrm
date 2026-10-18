# Part 1 — Meta app dashboard setup

**Campaign:** messenger-unified-inbox · **Plan:** `docs/messenger-behavior-contract.md` § Assumptions
**Stage:** Planning
**Code:** `main` (no code; Meta dashboard work)
**Done when:** Jafar's Facebook account has a role on the app and can pick his test Page; Facebook Login for Business is configured.

## Steps

- [x] Meta developer account works on this computer (2026-10-18)
- [x] App "Ucrm Messaging" created, App ID `1419027217062214`, Messenger + Instagram messaging use cases
- [x] `META_APP_ID`, `PUBLIC_META_APP_ID`, `META_APP_SECRET` saved in `.env` (secret never printed)
- [x] Jafar will test with a Facebook Page he already has (2026-10-18)
- [x] Test Page name: **Random News** (2026-10-18). [ ] Still confirm Jafar's Facebook profile is an admin of it
- [ ] Add Jafar and any tester under App roles
- [ ] In the app's Messenger use case, configure Facebook Login for Business so a Page admin can grant `pages_show_list`, `pages_manage_metadata`, `pages_messaging`, `pages_read_engagement`, `business_management`

## Next

Ask Jafar for the Page name. Then use Claude in Chrome (`tabs_context_mcp` first) on
`https://developers.facebook.com/apps/1419027217062214/` for roles and Login configuration. Jafar types passwords.
Do NOT add the webhook callback URL yet: Meta checks it immediately and our handshake route does not exist until
Part 5. Business Verification is Part 1b.

## Outside actions

- Meta app created — check: app 1419027217062214 appears at developers.facebook.com/apps — done

## Notes

`MESSENGER_VERIFY_TOKEN` must be generated in Part 5. The Chrome extension sometimes disconnects; ask Jafar to reconnect
it if tools report no browser. After a reconnect, call `tabs_context_mcp` again for new tab ids.

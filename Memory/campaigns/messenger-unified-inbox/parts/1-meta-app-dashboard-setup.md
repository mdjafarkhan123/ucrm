# Part 1 — Meta app dashboard setup

**Campaign:** messenger-unified-inbox · **Plan:** `docs/messenger-behavior-contract.md` § Assumptions
**Stage:** Planning
**Code:** worktree `.worktrees/messenger-campaign`, branch `claude/messenger-campaign`
**Done when:** Jafar's Facebook account has a role on the app and can pick a test Page; Facebook Login for Business is configured.

## Steps

- [x] Meta developer account works on this computer (2026-10-18)
- [x] App "Ucrm Messaging" created, App ID `1419027217062214`, Messenger + Instagram messaging use cases
- [x] `META_APP_ID`, `PUBLIC_META_APP_ID`, `META_APP_SECRET` saved in `.env` (secret never printed)
- [ ] Facebook Page for testing exists (Jafar creates one, or names an existing Page he admins)
- [ ] Add Jafar and any tester under App roles
- [ ] In the app's Messenger use case, configure Facebook Login for Business so a Page admin can grant `pages_show_list`, `pages_manage_metadata`, `pages_messaging`, `pages_read_engagement`, `business_management`

## Next

Ask Jafar which Facebook Page to use for testing. Then use Claude in Chrome (tab group opened by `tabs_context_mcp`) on
`https://developers.facebook.com/apps/1419027217062214/` to do the role and Login configuration. Jafar types passwords
and password prompts himself. Do NOT add the webhook callback URL yet: Meta checks it immediately and our handshake
route does not exist until Part 5.

## Outside actions

- Meta app created — check: app 1419027217062214 appears at developers.facebook.com/apps — done

## Notes

Meta's webhook callback URL and verify token are entered in Part 5. `MESSENGER_VERIFY_TOKEN` must be generated then.
The Chrome extension sometimes disconnects; ask Jafar to reconnect it if tools report no browser.

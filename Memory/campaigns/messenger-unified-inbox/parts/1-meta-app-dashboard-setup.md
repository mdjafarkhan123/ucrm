# Part 1 — Meta app dashboard setup

**Campaign:** messenger-unified-inbox · **Plan:** `docs/messenger-behavior-contract.md` § Assumptions
**Stage:** Planning
**Code:** `main` (no code; Meta dashboard work)
**Done when:** Jafar's Facebook account has a role on the app and can pick his test Page; Facebook Login for Business is configured.

## Steps

- [x] Meta developer account works on this computer (2026-10-18)
- [x] App "Ucrm Messaging" created (now App ID `1709471683925717` on the 2nd account; old `1419027217062214` abandoned), Messenger + Instagram messaging use cases
- [x] `META_APP_ID`, `PUBLIC_META_APP_ID`, `META_APP_SECRET` saved in `.env` (secret never printed)
- [x] Jafar will test with a Facebook Page he already has (2026-10-18)
- [x] ~~Random News~~ dropped 2026-10-23 (other account)
- [x] App roles checked 2026-10-23: Jafar Khan (2nd account) is Administrator; app is managed by business Uplift Contractor (portfolio link done). Add testers only if someone else must test
- [x] 2026-10-23: all five permissions "Ready for testing" in the Messenger use case (added `pages_read_engagement`). Facebook Login for Business configuration "Messenger Page connect" created: General, **User access token**, those five permissions. Configuration ID `1133535439212464` (public; Part 4 passes it as `config_id`)
- [x] Test Page is **Uplift Contractor** (Jafar 2026-10-23). Random News belongs to his other account — never use it

## Next

Part 1 is done. Valid OAuth redirect URIs and
app domains are set in Part 4 when the callback route exists; the webhook URL in Part 5.

## Outside actions

- Meta app created — check: app 1709471683925717 appears at developers.facebook.com/apps — done
- Login configuration created — check: Facebook Login for Business → Configurations lists "Messenger Page connect" — done 2026-10-23

## Notes

`MESSENGER_VERIFY_TOKEN` must be generated in Part 5. The Chrome extension sometimes disconnects; ask Jafar to reconnect
it if tools report no browser. After a reconnect, call `tabs_context_mcp` again for new tab ids.

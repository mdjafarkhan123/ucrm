# Part 6 — Inbox shows Messenger

**State:** Built and merged to main 2026-10-23 (branch `claude/messenger-part6`). Left: Jafar's look at the live inbox.

**Design (approved by Jafar 2026-10-23):** the whole unified inbox's new look, all channels — board `yjdF0`
(screen `np8WS`, reply box `j93I8l`, fold-up `jU783`, states `y2sz2l`), written up in
`.claude/skills/design/inbox.md`. Feel: a messaging app people know (WhatsApp, iMessage, Messenger), premium.
Followed GoHighLevel, HubSpot/Zendesk, Intercom, Front, Gmail, Slack (choice history in Git, `5664ffed`).

**Build slices** (look for everything the inbox does today + Messenger; Star, Archive, Mark as unread, Internal
comment and emoji need database work → a later part, no dead buttons meanwhile; tell Jafar):
1. ✅ Messenger data: feed returns `messenger` (Page, status, last_inbound_at); context returns `lifecycle_status`;
   helpers `conversationMessenger`, `messengerReplyWindow`, `messageRuns`, `isUnknownCustomer` (tests pass).
2. ✅ Tokens `--color-channel-*`; `inbox/ChannelMark.svelte` (Messenger logo path from Pencil `NVZqT`).
3. ✅ List card `inbox/InboxList.svelte` (Team/Mine, search + Unread filter menu, lanes, Needs reply/Earlier).
4. ✅ Chat header (channel marks, "New lead · Messenger", Details toggle; Details card ≥1180, drawer below).
5. ✅ Bubbles: `ConversationMessage.svelte` (runs, ticks, red failed, email card, scheduled); an empty badge row
   no longer adds 8px (single-line bubble 36 high, as drawn).
6. ✅ Reply box (`ConversationComposer`): Reply tab strip, Messenger reply-window chip, From/Subject rows,
   reason line, quiet tool bar with channel pill (`ComposerChannelMenu` now has marks + addresses), shortcut
   hint, one-line minimized state. Messenger is a channel; sending is held with "coming soon" until Part 7.
   SMS text-price pill and segment blocks (board `nLAe4`) belong to communications-activation, not built here.
7. ✅ Unknown-customer strip + `inbox/LinkToClientDialog.svelte`: Link to a client merges the lead into the
   picked client (`/api/clients/merge`; merge already moves Messenger identities). Inbox returns `can_merge`.
   Not yet run on live data — it deletes the test lead; needs Jafar's yes.
8. ✅ `ui/PaneResizer.svelte` drag lines; chat ≥400; container `inbox-chat` folds words at 640/480. Compared with
   Pencil 2026-10-23 (`np8WS`, `j93I8l`, `y2sz2l`): matches; tool icons changed to the drawn folder-open, file-text,
   bolt. Team / Mine stays the green app-wide switch (inputs.md rule; the drawing hand-drew it white). Not built
   (need database, later part): Star, Archive, Mark as unread, Internal comment, emoji, header ⋯ menu. Messenger
   tools stay hidden until Part 7 sends. Seen: the app-wide "Chat with Uplift" button covers Send — told Jafar.

**Checking screens:** Playwright scripts (session scratchpad: `login.mjs`, `shot.mjs`, `expand.mjs`, `narrow.mjs`)
log in once as the contractor owner (Login.md) against `npx vite dev --port 5210` in the worktree.

**Next:** Part 7 Reply. Full type check waits for the campaign's last step.

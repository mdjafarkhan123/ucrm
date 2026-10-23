# Part 4 — Connect and disconnect a Page

**State:** Done 2026-10-23 — connect, live test, disconnect and reconnect proven on the live app.

**Approved design:** Jafar chose **Option B · Connection hub** on 2026-10-23. Pencil `concept.pen`, Communications
row, board "Concept · Communications · Messenger · Facebook Pages · Approved B · 2026-10-23" (`tEAXY`). Screen
`s48fd`: green banner (Pages count, "needs you" pill, logged-in Facebook account, Connect a Page), one Pages list
(picture, status pill, last message, default star, ⋯, red reason strip with Reconnect), Live test panel, Good to
know card. Option A was deleted on approval.

**Also approved by Jafar 2026-10-23 (drawn on B):** Choose Pages pop-up, ⋯ menu (Make default, Reconnect,
Open on Facebook, Disconnect), Disconnect "are you sure?", empty welcome card, Live test arrived, couldn't-connect
strips, three reconnect reasons.

**Next:** a build session builds from the board (design sessions don't build). Jafar saved `concept.pen` 2026-10-23;
it is committed from main once the pen-tidy claim is released (its uncommitted changes share the file).

## Build approach (2026-10-23, branch `claude/messenger-part4-build`, worktree `.worktrees/messenger-part4-build`)

Followed: GoHighLevel's popup Facebook login + Page picker; Meta's manual Login-for-Business flow (`dialog/oauth`
with `config_id`, code → long-lived user token → `/me/accounts` Page tokens → `subscribed_apps`).
- Popup opens `/api/settings/communications/messenger/login` (state cookie) → Facebook → `/callback` saves an
  encrypted 30-minute login session (`communication_messenger_login_sessions`) and posts the result to the opener.
- Choose Pages reads `/pages` (Graph call with the session token, no tokens sent to the browser); `POST /connections`
  subscribes each Page, then saves it encrypted; reconnect revives the same row. Disconnect unsubscribes, wipes the key.
- Live test polls `/connections/[id]/test?since=` for the first message after the test began.
- Meta dashboard: add redirect URI `https://app.upliftcontractor.com/api/settings/communications/messenger/callback`.

## Proof so far (2026-10-23)
28 unit tests (graph, connections, crypto specs). Meta redirect URI saved ("Changes saved"). Live: Jafar finished
Facebook's window, Choose Pages showed Uplift Contractor, Connect 1 Page → row active, default, key encrypted, login
session deleted (org Raad LTD). Jafar messaged the Page twice → 2 inbound rows under one new lead "Facebook user", row Receiving, banner "1 new conversation"; light and dark look right. Disconnect (confirm pop-up, loading) → row disconnected, key wiped, 2 messages kept, welcome card. Reconnect → same row revived, old thread shown, "back again" joined the same lead (1 identity, 1 lead, 3 messages). Inbox labels it "Email conversation" — Part 6.

## Left over
- Whether Meta accepted the unsubscribe on disconnect is unverified (dev server log not readable); reconnect resubscribes anyway. Part 8 health check covers it.
- `--color-messenger` still needs its Pencil variable in `concept.pen` (pen-tidy claim held the file).

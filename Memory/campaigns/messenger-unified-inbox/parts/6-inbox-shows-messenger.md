# Part 6 — Inbox shows Messenger

**State:** Design — look chosen 2026-10-23; next: fold-up and states.

**Chosen (2026-10-23):** Claude reviewed A/B; Jafar repeated "timeline looks like a native messaging app people
know, also premium" and left the pick to Claude ("you do what you want"). Chosen: a WhatsApp Desktop mix on
board `yjdF0`, block `Z0nFi5`, screen `np8WS` (Details closed) plus the Details panel `PpowK` shown opening.
From B: Needs reply / Earlier list, Team / Mine, channel lanes, date chips, time
inside bubbles. From A: brand-green bubbles for yours (`color-interactive`, text `color-surface`), light grey for
theirs; the chat is one white card (header, messages, reply bar) — Jafar: the timeline must not blend with the page; labelled reply bar (Messenger ▾, reply window in words, Reply / Internal comment); labelled header buttons.
New: bubbles join up (radius-large, radius-small where they touch), tail on your last bubble; Seen only under
your last sent message; unread rows show green time + count; selected row `color-surface-active`; drag handle only
on hover. A and B deleted from the board (kept in Git, commit 5664ffed).
New Pencil colours `color-channel-email/-text/-chat` (not yet in code). Messenger logo is a brand mark, not
Tabler — design skill needs an exception.

**Followed:** GoHighLevel (channel mark on the contact picture, channel switch in the reply box); HubSpot/Zendesk
(name the Page; show time left to reply). Messenger mark = phosphor `messenger-logo` on `color-messenger` (variable
added to `concept.pen` 2026-10-23; Part 4 board now uses it).

**Jafar's direction (2026-10-23):** this part also designs the unified inbox's new look (all channels, not only
Messenger). The chat timeline must look, feel and behave like a native messaging app people know (WhatsApp,
iMessage, Messenger): grouped bubbles, avatar on a group's last bubble, times between groups, pill reply bar with a
round send button, premium Dribbble polish. He likes Option B's idea of hiding the customer details behind a
"Details" button (collapsible right panel) so the chat gets the room.

**Jafar's addition (2026-10-23) — buttons fold when a part shrinks:** labels drop to icons (tooltip on hover),
then the least-used buttons move into ⋯ one at a time from the right; Send, the channel switch and Details never
hide; ⋯ gets a dot when a hidden button is on (Star, Follow). Hide order — header: Archive → Star → Mark as unread →
Follow → Assign; reply box: emoji → files from the client → snippets; list: Filter label, then tabs fold into
"All ▾". Followed: Gmail, Front, Slack, Office (overflow menu).

**Next session:** draw the fold-up as wide / medium / narrow of `np8WS` (Details open = medium); then the states
(window closing soon, window closed with reason, Page disconnected, new "Facebook user" lead with Link to a client
pop-up, sending/sent/delivered/seen, failed). Missing from the drawing, keep from live: Message details pop-up,
Minimize composer, text credit / no permission notices. Add the brand-mark exception, channel colours and chat
bubble rules to the design skill. Show Jafar; a build session builds.

# Part 6 — Inbox shows Messenger

**State:** Design — look chosen 2026-10-23; reply box B approved; fold-up and states approved 2026-10-23. Design done; next: build.

**Chosen (2026-10-23):** Claude reviewed A/B; Jafar repeated "timeline looks like a native messaging app people
know, also premium" and left the pick to Claude ("you do what you want"). Chosen: a WhatsApp Desktop mix on
board `yjdF0`, block `Z0nFi5`, screen `np8WS` (Details closed) plus the Details panel `PpowK` shown opening.
From B: Needs reply / Earlier list, Team / Mine, channel lanes, date chips, time
inside bubbles. From A: brand-green bubbles for yours (`color-interactive`, text `color-surface`), light grey for
theirs; the chat is one white card (header, messages, reply bar) — Jafar: the timeline must not blend with the page; labelled reply bar (Messenger ▾, reply window in words, Reply / Internal comment); labelled header buttons.
New: bubbles join up (radius-large, radius-small where they touch), tail on your last bubble; Seen only under
your last sent message; unread rows show green time + count; selected row `color-surface-active`; drag handle only
on hover. A and B deleted from the board (in Git, 5664ffed).
New Pencil colours `color-channel-email/-text/-chat` (not yet in code). Messenger logo is a brand mark, not
Tabler — design skill needs an exception.

**Followed:** GoHighLevel (channel mark on the picture); HubSpot/Zendesk (name the Page, time left to reply).

**Jafar's direction (2026-10-23):** this part also designs the unified inbox's new look (all channels, not only
Messenger). The chat timeline must look, feel and behave like a native messaging app people know (WhatsApp,
iMessage, Messenger): grouped bubbles, avatar on a group's last bubble, times between groups, premium Dribbble polish. He likes Option B's idea of hiding the customer details behind a
"Details" button (collapsible right panel) so the chat gets the room.

**Jafar's addition (2026-10-23) — buttons fold when a part shrinks:** the full rule and hide order are in the
note of fold-up section `jU783` (followed Gmail, Front, Slack, Office).

**Reply box — Approved B (Jafar, 2026-10-23):** section `j93I8l` on `yjdF0` (four states), now in `np8WS`. Team inbox box: Reply / Internal comment tabs on its top edge,
tools along the bottom, Send in words; Internal comment turns it yellow. Followed Intercom, Front, GoHighLevel.

**Approved by Jafar 2026-10-23:** fold-up `jU783` (medium screen with Details open, narrow chat 400 with ⋯
menus, list at 240, drag-line hover) and states `y2sz2l` (window closing/closed + channel menu, Page disconnected,
texts stopped / no permission, minimized box, Message details, ticks sending→seen/failed, "Facebook user" + Link
to a client).

**Jafar's later changes (2026-10-23), in place:** Seen = filled circle with a double tick, no line under the
message (hover tip + Message details show times); failed message = whole bubble red.

**Design skill updated 2026-10-23:** `.claude/skills/design/inbox.md` (whole inbox look), channel colours in
`colors.md`, channel pill in `chips.md`, brand-mark exception in `icon-shapes.md`.

**Next:** a build session builds the inbox look from `inbox.md` and board `yjdF0` (Svelte, live inbox), then
live screenshots beside the Pencil frames. Then Part 7 Reply.

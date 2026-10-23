# Conversations Inbox

> Dependencies: `colors.md`, `buttons.md`, `inputs.md` (reason line, text price), `chips.md` (channel pill, sender
> chip), `avatars.md`, `modals.md`

The inbox for every channel: Messenger, text, email, website chat. Pencil: `concept.pen` board "Concept ·
Communications · Messenger · Inbox · Approved · 2026-10-23" (`yjdF0`): screen `np8WS`, reply box `j93I8l`,
fold-up `jU783`, states `y2sz2l`, approved by Jafar 2026-10-23. It should feel like a messaging app people already
know (WhatsApp, iMessage, Messenger), with premium polish.

## Layout

- On the page colour, three white cards side by side, 4 apart: the list (300), the chat (fills), and Details
  (310, closed by default). Each card is `--color-surface`, 1px `--color-border`, `--radius-large`, clipped.
- Between two cards is a 9-wide drag line, invisible at rest. On mouse-over: a 3px `--color-interactive` line, a
  15×44 white grip with a 1.5px `--color-interactive` edge and three 3px green dots, and the dark tooltip
  "Drag to resize · double-click to reset" with `move-horizontal`.

## List

- Header (padding 18 16 10, rows 12 apart): the inbox tile, the Team / Mine segmented switch, the main New button; under it search with
  a filter icon at its right; then the channel lanes: a `--color-surface-hover` track (radius 10, padding 3)
  holding All plus one lane per channel mark.
- Groups "Needs reply · 3" and "Earlier": 12/600 uppercase `--color-text-secondary`.
- Row: radius 10, padding 10, gap 12: 40 avatar; name 14/700 heading with its channel mark (14) before it, the time
  12/600 at the right; the preview 14/500 `--color-text`. Unread: green time (`--color-interactive`) and a 20-high
  green count pill (white 12/600). Picked row: `--color-surface-active`. An unknown customer's avatar is
  `--color-inactive-surface` with a `user-round` icon.

## Channel marks

- Messenger uses Messenger's own logo in `--color-messenger`: the one brand mark in the app, in place of a Tabler
  icon, because customers recognise it.
- Email, Text and Website chat are small app-style tiles: a radius-4 square in `--color-channel-email`,
  `--color-channel-text` or `--color-channel-chat` with a white glyph (14 or 16).
- Inside a green bubble the mark turns white.

## Chat card

- **Header** (68 high, padding 0 16 0 20, hairline under): 40 avatar; name 16/600 heading with a star when starred;
  under it the channel marks and "Client · Messenger, text and email" 12 quiet. At the right, raised white keys:
  Assign (assignee avatar, name, chevron), Follow, Star, Archive, Details (icon + word; switched on while open),
  then ⋯.
- **Timeline** (padding 12 24, newest at the bottom): date chips centred (pill, `--color-surface-active`, 12/600
  quiet, padding 5 12).
- **Their bubbles:** `--color-surface-active`, text 14 heading. **Yours:** `--color-interactive` with
  `--color-surface` text, at the right. Padding 8 12 7 14; corners `--radius-large`, with `--radius-small` on the
  corner where bubbles in a run touch; your last bubble in a run has a small tail. Bubbles 3 apart within a run, 5
  between runs. An email is a white card bubble (400 wide, 1px border) with its subject line.
- **Inside each bubble**, bottom right, all solid `--color-surface` on green: the channel mark 12, the time 12, and
  on yours the tick: `clock-3` sending (bubble at 70%), `check` sent, `check-check` delivered, and once read an 18
  filled `--color-surface` circle holding a 12 green `check-check` (`--color-interactive`), so Seen stands apart from Delivered.
- **No line under the message.** Hovering the ticks shows the dark tooltip with the mark and "Seen at 9:26 AM · click for
  details" 12/600; clicking them opens Message details, which lists Sent, Delivered (`check-check` quiet) and Seen
  (a 16 filled `--color-interactive` circle with a white `check-check`) with their times.
- **Failed:** the whole bubble turns `--color-critical-surface` with a 1px `--color-critical-surface-edge`; its words,
  mark and time `--color-critical-on-surface`, no tick (and its tail in the surface colour). Under it `circle-alert`
  and the reason 12 `--color-critical`, then "Retry" 12/700 `--color-interactive`.
- **Internal comment in the timeline:** a centred yellow pill (`--color-warning-surface`, its edge, `lock`, words
  12/600 `--color-warning-on-surface`).
- **Scheduled:** a `--color-surface-background-subtle` bubble with a 1px edge, `calendar-clock` and the send time in
  `--color-time`; under it "Scheduled by email · Edit Cancel".

## Reply box

Inside the chat card's foot (padding 4 20 20). One writing box: `--color-surface`, 1px
`--color-border--interactive`, radius 12, clipped. While typing: 1.5px `--color-interactive` edge and a soft green
glow.

- **Tab strip** (40 high, hairline under): tabs "Reply" (`reply`) and "Internal comment" (`lock`), 14/600, padding
  0 10; the chosen tab has a 2px underline, `--color-interactive` for Reply and `--color-warning` for Internal comment.
  At the right: the reply-window chip, then Minimize (`minus`) and Full screen (`maximize-2`) as 32 quiet icon buttons.
- **Reply-window chip** (Messenger): 24 high pill, 12/600. More than an hour left: informative family, `timer`,
  "23 h 17 min left to reply on Messenger". Under an hour: warning family, `alarm-clock`. Closed: critical family,
  `timer-off`, "Reply window closed". Page disconnected: critical, `unplug`, "Page disconnected".
- **Email adds** two 44-high rows under the tabs, each with a hairline: "From" + the sender chip → the address; then
  "Subject" 13/600 quiet + the subject 14/600.
- **Writing area:** padding 12 16 8, 14 heading at line height 1.5; empty: three lines tall, placeholder "Write your
  reply to Daniel…" quiet. It grows as you type. Files sit under the words as file cards (48 high, radius 10, 40 photo,
  name 13/600, kind and size 12 quiet, ×).
- **Tool bar** (padding 8 8 8 10, gap 4): the channel pill ("Messenger · Uplift Contractor Page ▾"), a 1×20
  divider, then 32 quiet icon buttons: upload a file, files from the client, email templates (email only), snippets,
  emoji. At the right: the shortcut hint ("Ctrl ↵", 12/600 quiet on `--color-surface-background`, radius 4) and
  Send: the main button with the word and `send`; email adds a joined chevron for Send later. Nothing typed: Send is
  disabled. A text shows its price in the button (`inputs.md`, Text price in the reply box).
- **Internal comment:** the whole box turns `--color-warning-surface` with its edge; the strip says "Only your team
  sees this" (`eye-off`); the tools are mention, upload and emoji in `--color-warning-on-surface`; the button reads
  "Add comment" with `lock` (still brand green). A mention is a small white chip with the name 14/600 green.
- **Reason line** when sending is blocked: under the tab strip, padding 10 12 0, the reason line from `inputs.md`;
  the placeholder says why in `--color-disabled`. Reply window closed: critical with "Reply by text". Page
  disconnected: critical with "Reconnect in Settings". Texts stopped: critical with "See Messaging in Details". No
  permission yet: warning, same link.
- **Channel menu** (dropdown list, 300 wide): each line its mark, the name and the address 12 quiet; the current one
  600 with a green check; a channel that can't send right now is greyed with its reason 12 `--color-critical-on-surface`.
- **Minimized:** one 52-high line in the same box: channel pill, "Write your reply to Daniel…", a 32 `chevron-up`
  key, and a disabled 36 send square.

## Unknown customer

- Header: grey `user-round` avatar, name "Facebook user", "New lead · Messenger", Assign "Unassigned".
- Under the header, a full-width informative strip (padding 12 20): `user-search`, "Is this someone you already
  know?" 14/600 and one line 12 in `--color-informative-on-surface`, and a white "Link to a client" key (`link`).
- Link to a client pop-up (440): client tile `link`, search box, client rows (32 avatar, name 14/600, address and
  phone 12 quiet; picked row `--color-surface-active` with a green `circle-check`), one 12 quiet line saying what
  linking does, footer Cancel + "Link to Daniel Brooks" (main, `link`).

## Narrow widths

Words go first, then buttons fold into ⋯ one at a time; Send, the channel pill and Details always stay.

- **Header:** Assign shows only the avatar and Details only its icon (it stays switched on while open); then Archive,
  Star, Mark as unread, Follow and Assign move into ⋯ in that order. The ⋯ menu lists hidden buttons first, a switched-on
  one with a green "✓ On" pill; ⋯ carries an 8 green dot with a white ring while a hidden button is on.
- **Reply box:** the chip shortens ("23 h left", then "23 h"); the channel pill drops the Page name; the tabs drop their
  icons; then emoji, files from the client and snippets move into a ⋯ More tools button
  (`--color-surface-hover`).
- **List:** New shows only its icon; the lanes fold into one "All channels ▾" key pill.

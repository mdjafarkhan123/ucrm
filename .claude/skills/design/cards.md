# Cards

> Dependencies: `colors.md`, `radius.md`, `borders.md`, `icon-shapes.md`, `typography.md`

## Core Specs

- Background `--color-surface`; 1px `--color-border`; radius 16; no shadow.
- **Title area:** every white card with a title starts with the one shared **Card header** part (Pencil:
  "Card header" on the Parts board), so a change to it reaches every card (Jafar, 2026-10-18): a 40 icon tile in
  the card's meaning colour, the title 20/600 (`--typography--fontSize-larger`, -0.2), an optional 12 quiet hint
  under it, the card's actions at the right, padding 16 20 (`--space-base` `--space-medium`; 14 16 in a narrow
  right column), and a full-width 1px `--color-border` line underneath. The body below has padding 20
  (`--space-medium`) and gap 16. A table head right under the header supplies that line itself.

## Section card and side card

- **Section card** (a block of a page): the Card header, then a body with padding 20 and gap 16.
  - Facts: rows of label (13/500 `--color-text-secondary`, 140 wide) and value (14/500 `--color-heading`),
    padding 10 0, a 1px `--color-border` line between rows.
  - List: rows run edge to edge, padding 14 20, a 1px line between rows, no body padding.
  - A group inside a card is never a second card: a 1px `--color-border` line above, 16 space, a 16/600 title
    and a 12/500 quiet hint, then its fields 12 below.
- **Side card** (in the 360 side column): the same, with the header padding 14 16 and body padding 16. A count
  goes in the hint line ("3 tags · used to filter clients").
- The header tile's colour is what the card is about: a record, or a part of the app (`colors.md`).

## Side card rows (Discount and tax)

Approved 2026-10-20, Pencil board "Batch 24 · Discount, tax and totals".
- One row per setting inside a side card, edge to edge: padding 14 16, gap 12, a 1px `--color-border` line
  above. A 32 tile (`--color-inactive`; `--color-warning` while it waits on a choice), the label 12/500 quiet
  over the value 14/600 heading (an optional 12 quiet line under it), the amount 14/600 heading at the right,
  then a 32 pencil icon button when it can be changed.
- Nothing chosen: the value is quiet ("None added"); waiting on a choice: the value in `--color-warning--onSurface`
  ("Not configured"). No pencil when it can't be changed; no access shows "No access to prices" quietly.
- The card's header tile takes the record colour (quote pink, invoice blue).

## Totals card

- Side card with a calculator tile in the record colour ("Overview"); body padding 16, gap 12.
- Lines: label 14/500 quiet, figure 14/600 heading, spread apart. Discount and tax lines show only when set.
- Total band: record `--surface` fill with its `--surface-edge` 1px, radius 8, padding 12 14; "Total" 14/600
  in the record `--onSurface`, the figure 24/700 heading (-0.4).
- Team-only panel (cost, estimated profit, margin): `--color-surface--background`, 1px `--color-border`, radius
  8, padding 12 14, gap 10; a 14 lock and "Only your team sees this" 12/600 quiet; profit in
  `--color-success--onSurface`; a 6 high margin bar (`--color-border` track, `--color-success` fill).
- No access: a 16 `eye-off` in `--color-informative` before the quiet sentence.

## Money summary card

The one card at the top of the rail on job, quote and invoice pages; the frame stays the same and the content
follows the record (colours in `colors.md` → Money Card Colours).

- Gradient `--color-money--start` → `--end`, 1px `--color-money--border`, radius 16, padding 24, gap 20, 360 wide.
- Header: a 12/600 uppercase eyebrow (0.8 tracking, white 72%) and a right chip (`--color-feature--subtle`,
  1px `--color-feature--border`, round, 14 icon + 13/600 white): "Team only" with a lock, or the invoice due date.
- Figure: the big number 32/700 (-0.6) white with a pill beside it (margin, below target, losing money, or the
  invoice's share of the job); a 13 white 72% line under it ("On $8,000 of work, before tax").
- Bar: 10 tall, 3 apart, round ends; then legend rows (8 square dot radius 2, label 14 white, share 14 white 72%,
  amount 14/600 white, profit and loss amounts in their colour).
- Foot: a 1px `--color-feature--border` line, then rows (14 icon white 72%, label 14 white 72%, value 14/600).
- Without cost rights: only the total and a quiet eye-off line; no bar, no profit.

## Automatic follow-up card

The side card on a Request and a website chat that shows an inquiry's automatic reply (board "Concept · Batch 41 ·
Automatic follow-up card · Approved B", `jXc9n`, Jafar 2026-10-21).

- Card header with a 40 `--color-conversation` tile (`bot`) and a 12 quiet hint; body padding 16, gap 14.
- Each running follow-up is a panel in its status colour: `--surface` fill, 1px `--surface-edge`, radius 12,
  padding 14, gap 12. Waiting `informative`, paused or stuck `warning`, needs attention `critical`.
  - Top: the follow-up name 13/600 in the status `--onSurface`, the outlined status pill at the right.
  - When: a 12/500 quiet kicker ("Next step", "On hold") over the big line 24/700 heading (-0.4): the next send
    time; when paused or failed the reason is the big line at 20/700 with a 12 `--color-text` line under it.
  - Trail: a 20 filled circle with a white 12 check per message sent, joined by 14×2 lines, then a 20 white ring
    (2px status colour, 6 dot) for the next step, and "1 message sent" 12/500 quiet.
  - Stuck or failed: a strip (`--surface`, 1px edge, radius 8, padding 7 10, 14 icon, 12/500 `--onSurface`).
  - Actions: three small buttons sharing the width, 6 apart: Pause (secondary; Resume as the green main button
    when paused), Skip, Stop (danger). No buttons for view-only people or a failed follow-up.
- Finished and stopped follow-ups: under a 1px line, an EARLIER overline, then one line each: a 24 tile,
  name 13/600 over the outcome or stop reason 12 quiet, the status pill at the right.
- The Stop pop-up is the danger "are you sure?" pop-up with a slip under the heading naming what stops
  (`--color-surface--background`, 1px edge, radius 8, padding 12 14: 32 conversation tile, name 14/600, sent
  count and next step 12 quiet), then the message and the optional reason box.

## Anatomy (stat card)

1. Header: 32 tile + title 14/600 + quiet open icon (arrow-up-right) at the right.
2. One big number, 32 (`--typography--fontSize-stat`)/700 `--color-heading`.
3. Footer: a status pill and a 13px quiet line ("across 9 invoices").

## Feature card

- The one card a screen leads with (Home: greeting, day summary and day clock). At most one per screen; never on a
  card full of record tiles or status pills.
- Linear gradient `--color-feature--start` → `--color-feature--end`, plus a radial `--color-feature--glow` at the
  top right; no border; radius 16; padding 24 32.
- Text `--color-feature--text` (title 28/700 `--typography--fontSize-display`, -0.6) and
  `--color-feature--text--secondary`. Panels inside: `--color-feature--subtle` with 1px `--color-feature--border`,
  radius 16; their icons white. A white secondary button sits on it unchanged.

## Number card

Approved B, 2026-10-21: `concept.pen` → "Batch 33 · Number cards on list pages" (`fzPaM`).
The same card shows status counts, report numbers and the green summary at the end of a list overview.

- White, 1px `--color-border`, radius 16, padding 16 12 14, gap 12. Cards stand directly on the page,
  12 apart and the same height within a row. No outer white overview card.
- Head: a 48 tile with a 24 icon, then the number 30/700 (-0.8), with its short label 13/600 right under it,
  4 apart, beside the tile. Head gap 10. Number uses `--color-heading`; label uses the status `--onSurface`.
- A clickable card has a 16 arrow in its top-right corner. Its whole area is the link or filter button.
  Hover uses `--color-surface--hover` and the interactive hover border; active uses `--color-surface--active`.
  A picked filter has a 2px inset `--color-interactive` ring; keyboard focus keeps `--shadow-focus` outside it.
- Note band at the bottom: `--color-surface--background`, radius 8, padding 8 10, text 12/500 quiet,
  line height 1.4. Supporting figures share this band, with their figures 14/700.
- Status colours: waiting `warning`, planned `informative`, done `success`, act now `critical`,
  stopped or draft `inactive`. An act-now card with a count uses `--color-critical--surface`, its edge and
  `--onSurface` text, with a white icon tile and white note band. Zero keeps the white card.
- Green summary: the same anatomy, `--color-feature` gradient and text tokens, feature tile and a bordered
  feature-subtle note band. A little wider on desktop so the figure fits. The same in light and dark mode.
- Fixed sets: Clients 4, Quotes 5, Invoices 5, Requests 6, Jobs 6, Reviews 4 (subject to existing permission).
  Narrow layouts wrap evenly: six cards become 3+3, then 2+2+2. All text stays at least 12px.
- The overview's title and facts sit above the row on the page: a 32 record tile beside title 16/600 over
  hint 12; facts use a 24 tile, figure 14/700 and label 13 quiet. Tags remain below when present.

## States

- Static: no hover.
- Clickable: hover `--color-surface--hover`, pointer cursor.

## Rules

- One job per card: one number or one list, one action.
- Cards in a row share the same height.

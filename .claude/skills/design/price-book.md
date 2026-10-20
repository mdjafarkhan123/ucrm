# Price book

> Dependencies: `colors.md`, `inputs.md`, `badges.md`, `buttons.md`, `modals.md`, `cards.md`, `lists.md`

Pencil: `concept.pen` → board "Price book" (`ZWTSi`), approved 2026-10-20.

Products are `--color-quote` (pink, `package`); services are `--color-job` (green, `wrench`), as on the Products
and services card.

## Search list under a line's name

The dropdown list (`inputs.md`) that opens under a line's name box: 4 under the box, radius 16, 1px
`--color-border`, `--shadow-base`, clipped; it may be wider than the box.

- **Group label** per type, padding 8 10 4 10, gap 8: a 20 type tile (radius 6), the word 12/600 in the type's
  `--onSurface` colour, then "· 2" 12 `--color-text-secondary`. Products come before services.
- **Picture cards** first in each group, for items with a photo: two to a row, 10 apart. Card: white, radius 12,
  1px `--color-border`, clipped; the photo 84 high (cover) with a 22 type badge (radius 6, type surface and icon)
  8 in from its top-left; under it, padding 10 12 12, the name 13/600 heading (wraps) then the price 14/700 heading
  and the unit 11 `--color-text-secondary`, 4 apart.
- **Rows** after the cards, for items without a photo: 44 high, padding 0 10, gap 10, radius 8. A 32 spot
  (`--color-surface--background`, radius 8, 14 `image` `--color-icon-secondary`), the name 14/600 heading over
  "description · unit" 12 `--color-text-secondary`, the price 14/600 heading at the right. Long names end in "…".
- **Pointed at:** a row fills `--color-surface--hover` with a 2px `--color-interactive` left edge; a card gets a
  2px `--color-interactive` ring.
- **Foot:** `--color-surface--background--subtle`, 1px `--color-border` line above, padding 8 8 8 14, gap 10:
  "Or keep typing for a one-off line." 12 `--color-text-secondary`, then a small secondary "New item" button
  with a `--color-interactive` plus.
- **Searching:** three row shapes in `--color-border` (32 square, two bars, a price bar).
- **No match:** padding 16, gap 12: a 32 `--color-informative` tile (`pencil-line`), "Not in your price book"
  13/600 over "“gutter guard” will be a one-off line on this job." 12 quiet; the foot reads "Sell it often? Save it
  to the price book."

## New item pop-up

A form pop-up (`modals.md`) 940 wide, in two sides, with no header line.

- **Preview side**, 340 wide, padding 28, gap 20, the feature card's fill (`cards.md`: gradient plus glow), white
  text. From the top: a 32 feature tile (`eye`) and "ON A QUOTE IT LOOKS LIKE" 11/600 uppercase
  `--color-feature--text--secondary`; the quote line as a `--color-feature--subtle` panel (1px
  `--color-feature--border`, radius 16, padding 14, gap 12) holding a 44 feature tile with the type icon, the
  name 14/600 and the description 12; "Customer pays" 13 over the price 32/700 (-0.8) with the unit 14; the profit
  bar (`colors.md`, cost in `--color-feature--labor` for a service and `--color-feature--items` for a product, the
  part you keep in white); a legend panel (radius 8, padding 12 16, gap 10: 8 dot, label 13, value 13/600 at the
  right: the cost, then "You keep $140.00 · 40%"); white chips 28 high (pill, padding 0 10, 14 icon and 12/600
  label in `--color-feature--start`) for Taxed and Labor; at the foot an `info` icon and a 12 note that saved
  quotes keep their price.
- People who may not see costs get no profit bar, legend or cost.
- **Form side**, padding 24 20 8 28 for the header: the title 24/700 (-0.5) over a 14 `--color-text-secondary`
  line, the × icon button at the right. Body padding 16 28 24, gap 20.
- **Type cards:** two side by side, 12 apart. White, radius 12, 1px `--color-border`, padding 14, gap 12: a 40
  type tile, the label 14/600 over a 12 quiet hint, a 20 round mark at the right. Chosen: 1.5px
  `--color-interactive` edge, `--shadow-button`, the mark filled `--color-interactive` with a white 12 check.
- Name box, then the description box (88 high) with a 112×88 photo box (`files.md`) beside it, 12 apart.
- **Price strip:** a label "Price" 13/600 with "· markup follows cost and price" 12 quiet; one box 64 high,
  radius 12, 1px `--color-border--interactive`, clipped, split by 1px `--color-border` lines into Unit cost,
  Markup, Unit price and a 110 Unit cell. Each cell padding 10 14: the label 11/600 uppercase quiet over the value
  16/600 heading with its "$" or "%" 16/500 quiet. The Unit price cell fills `--color-surface--background--subtle`
  and its value is 700.
- **Options:** one bordered list (radius 12, 1px `--color-border`), rows padding 12 16, gap 12, a line between
  them: a 32 tile (Labor `--color-time` `hard-hat`; tax `--color-invoice` `receipt`), the label 14/600 over a 12
  quiet hint, the checkbox at the right.
- **Footer:** the shared footer bar with a 16 `book-open` and "Goes into your price book" 13 quiet at the left,
  then Cancel and the main "Create item" button with a check.

## Price book drawer

A side drawer (`modals.md`) 480 wide: a 40 `--color-inactive` tile (`book-open`), "Price book" with "Add what
you already sell".

- **Controls**, padding 16 20 12, gap 12: the search box, then the segmented switch (All, Products with a pink
  `package`, Services with a green `wrench`; options 28 high) and a quiet green "+ Create new item" at the right.
- **Rows** run edge to edge, padding 10 20, gap 12: a 40 photo (radius 10) or a 40 `image` spot, then the name
  14/600 heading, the description 12 quiet, and a meta line of the type tag (the status pill, padding 2 8, 11/600,
  in the type colours) then "unit · Cost $110.00" 12 quiet; the price 14/600 heading at the right.
- **Add:** a 32 round `--color-interactive` button with a white 16 plus, `--shadow-button--raised`.
- **Added:** the row fills `--color-surface--hover` with a 2px `--color-success` left edge; the button becomes a
  32 high `--color-success` chip (pill, padding 0 10) with a white check and the count 13/700, then a 32 round
  white bordered "Add again" with a `--color-interactive` plus.
- **Footer:** a 24 `--color-success--surface` tile with a check and "3 lines added" 13/600 heading at the left,
  then a secondary "Custom line" with a green plus and the main "Done" with a check.
- Empty, nothing matches and couldn't load use `page-states.md` in the list area.

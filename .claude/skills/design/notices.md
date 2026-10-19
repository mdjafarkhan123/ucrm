# Notice strip

> Dependencies: `colors.md`, `radius.md`, `icon-shapes.md`, `buttons.md`

A message that stays in place until its cause is fixed, on a page or inside a card or pop-up.

## Core Specs

- Fill `--color-<tone>--surface`; no border; radius 16; padding 12; gap 12; items centred.
- Left: a 32 white tile (`--color-surface`, radius 8) with a 16 icon in `--color-<tone>`; the yellow family
  uses `--color-warning--onSurface`.
- Message: 14/500, line height 1.45, `--color-<tone>--onSurface`, fills the width.
- Right: at most one secondary button (`buttons.md`) when there is something to do. No close button.

## Tones

| Meaning | Tone | Icon |
|---|---|---|
| Good to know | `informative` | info |
| Done | `success` | circle-check |
| Needs a look | `warning` | triangle-alert |
| Something failed | `critical` | circle-alert |

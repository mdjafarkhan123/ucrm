# Icon Tiles

> Dependencies: `colors.md`, `radius.md`

## Core Specs

- A tile is a rounded square: background `--color-<meaning>--surface`, icon `--color-<meaning>`.
- Soft depth, so a tile never fades into a white card: the background runs top to bottom from
  `--color-<meaning>--surface` to `--color-<meaning>--surface-edge`, with a 1px `--surface-edge` border and an
  inset 0 1px 0 `--color-tile--highlight` top light. In dark mode those tokens fall back to the plain tile.
- Icons: Tabler in code, the Lucide icon with the same meaning in Pencil; icon is half the tile size.

## Sizes

| Tile | Icon | Radius | Use |
|---|---|---|---|
| 24 | 12–14 | 6 | Small lists, table cells |
| 32 | 16 | 8 | List rows, card headers |
| 40 | 20 | 10 | Large cards, page headers |

## States

- The sidebar has no tiles: its icons stand alone in their meaning colour (`sidebars.md`).

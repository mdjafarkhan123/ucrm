# Icon Tiles

> Dependencies: `colors.md`, `radius.md`

## Core Specs

- A tile is a rounded square: background `--color-<meaning>--surface`, icon `--color-<meaning>`.
- Hairline edge, so a tile never fades into a white card: a 1px `--color-<meaning>--surface-edge` border
  (the next palette step). In dark mode the edge token falls back to the tile colour.
- Icons: Tabler in code, the Lucide icon with the same meaning in Pencil; icon is half the tile size.

## Sizes

| Tile | Icon | Radius | Use |
|---|---|---|---|
| 24 | 12–14 | 6 | Small lists, table cells |
| 32 | 16 | 8 | List rows, card headers |
| 40 | 20 | 10 | Large cards, page headers |

## States

- The sidebar has no tiles: its icons stand alone in their meaning colour (`sidebars.md`).

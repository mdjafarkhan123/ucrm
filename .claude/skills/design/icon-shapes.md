# Icon Tiles

> Dependencies: `colors.md`, `radius.md`

## Core Specs

- A tile is a rounded square: background `--color-<meaning>--surface`, icon `--color-<meaning>`.
- Icons: Tabler in code, the Lucide icon with the same meaning in Pencil; icon is half the tile size.

## Sizes

| Tile | Icon | Radius | Use |
|---|---|---|---|
| 24 | 12–14 | 6 | Sidebar items, small lists, table cells |
| 32 | 16 | 8 | List rows, card headers |
| 40 | 20 | 10 | Large cards, page headers |

## States

- **Current page (sidebar):** solid tile in `--color-<meaning>`, icon `--color-text--reverse`.

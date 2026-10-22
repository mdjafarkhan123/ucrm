# Batch 62 · White buttons — options drawn

- **Why:** Jafar 2026-10-22: the brand-green edge on white buttons (set 2026-10-21, `buttons.md`) "does not look
  premium". Every white button on a screen wears the main button's green, and a switched-off button looks the
  same as a switched-on one.
- **Board:** `concept.pen` → `SU6gO` "Concept · Batch 62 · White buttons · Options A and B" (right of `bM4k0`).
  Sections: Today (live look), Option A, Option B, Dark mode (A and B).
- **Option A · soft grey edge:** white, 1px `--color-border--interactive` (same as field boxes), `--shadow-button`;
  hover edge `--color-border--interactive--hover`; danger keeps the grey edge with red text.
- **Option B · raised key, no line:** no stroke; soft shadow ring + small drop shadow + faint bottom inner shade,
  white→`--color-surface--hover` top-to-bottom. Dark: `--color-surface--hover` key with a faint top highlight.
  Needs new shadow tokens if chosen.
- Both: green only on the main button and a switched-on button; sizes, places and behaviour unchanged.
- **Next:** Jafar picks A or B → delete the other, change Pencil components `qpjlj`, `nkuNU`, `nIDZt`, `oxEbC` and
  the Parts board states, update `buttons.md`, `borders.md` and guide rule 7, then a builder changes `ui/Button`
  white kinds and joined groups. Concept.pen needs Jafar's Ctrl+S before any commit.

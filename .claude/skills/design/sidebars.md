# Sidebar

> Dependencies: `colors.md`, `typography.md`

The sidebar is the live app's sidebar (Jafar, 2026-10-18). Pencil: `concept.pen` → Sidebar part and the board
"Live sidebar · coloured icons".

## Core Specs

- A floating card: width 248; background `--color-surface`; 1px `--color-border`; radius 16; padding 18 14 16;
  gap 18; it sits 12 from the page edge.

## Anatomy

- **Workspace switcher:** a bordered box on `--color-surface--background--subtle` (radius 16, padding 10) with a
  40 logo tile (`--color-interactive`, radius 12, white leaf or the business logo), business name 15/700 over
  "Workspace" 12 quiet, and the collapse button (18 icon) at the right.
- **Groups:** uppercase label 11/700, 0.8 letter-spacing, quiet colour. Order: Overview: Home, Schedule,
  Timesheets · Customers: Inbox, Clients, Requests, Pipeline · Work & Money: Jobs, Quotes, Invoices, Files ·
  Growth: Marketing, Reviews. Settings sits at the bottom behind a 1px rule.
- **Item:** height 38, padding 0 10–12, gap 10–12, radius 12; an 18 icon in its meaning colour (`colors.md`), no
  tile behind it; label 14/500 `--color-heading`; optional count pill (20 high, `--color-interactive`, white
  11/700).

## States

| State | Look |
|---|---|
| Hover | Background `--color-surface--hover` |
| Current page | Background `--color-interactive` (`--color-interactive--hover` on hover); icon and label `--color-surface`, label 600; the count pill flips to `--color-surface` with `--color-interactive` text |
| Collapsed | 76 wide; logo, expand button and one icon per page; a count becomes an 8px dot |

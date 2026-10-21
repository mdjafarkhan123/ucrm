# Typography

> Dependencies: `colors.md`

## Core Rules

- **Font:** Inter (`--typography--fontFamily-normal`).
- **Titles and numbers:** `--color-heading`. Body: `--color-text`. Labels and hints: `--color-text--secondary`.
- **Case:** sentence case; uppercase only for small group and table labels.

## Scale

Jafar's table, 2026-10-21: the small text grows (nothing under 12; dates, pills and labels 14) while normal text
and the headings keep their sizes. Contractors are often older and need readable small text.

| Role | Size | Weight | Letter-spacing |
|---|---|---|---|
| Greeting on a feature card, record title | 28 (`-display`) | 700 | -0.6 |
| Page title | 24 (`-largest`) | 700 | -0.5 |
| Section title | 20 (`-larger`) | 700 | 0 |
| Big number on a card | 34 (`-stat`) | 700 | -0.8 |
| Card title (Card header) | 20 (`-larger`) | 600 | -0.2 |
| Bigger text (record header client name, tabs) | 16 (`-large`) | 600 | 0 |
| Stat card title | 14 (`-base`) | 600 | 0 |
| Row title, button | 14 (`-base`) | 600 | 0 |
| Body | 14 (`-base`) | 400–500 | 0 |
| Field label, small button | 14 (`-label`) | 600 | 0 |
| Meta, dates, pills | 14 (`-small`) | 400–600 | 0 |
| Group and table labels, tiny labels | 12 (`-overline`, `-smaller`), uppercase for group labels | 600 | 0.6–0.8 |

## Rules

- **Nothing under 12.** Every piece of text is at least 12px: labels, tags, pills, file-type marks, chart
  axes (Jafar, 2026-10-20). `-overline` and `-smaller` are 12 too.
- One page title per screen; headings in order.
- Money and counts use the heading colour and 600–700 weight.

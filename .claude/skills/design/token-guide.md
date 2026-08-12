# Color Tokens — Usage Guide

> Live source: `src/lib/styles/_variables.scss` .
> Every color is a semantic CSS custom property — paint with `var(--token-name)`, .

Where each `--color-*` token is meant to be used

## How to read this guide

Color system has two layers:

- **Base palette** (`--color-base-*`) — raw 100→1000 swatches. **Never use directly.**
- **Semantic layer** (`--color-*`) — the meaningful names that map to UI usage. **Always use these.**

All status/workflow colors follow a 3-part pattern:

| Suffix        | Meaning                                        |
| ------------- | ---------------------------------------------- |
| (none)        | the main color — labels, icons, filters, dots  |
| `--surface`   | the background tint for that status pill/badge |
| `--onSurface` | text/label **on top of** the surface tint      |

---

## Brand

The app brand visual language.

| Token                      | Value        | Use for                                                                |
| -------------------------- | ------------ | ---------------------------------------------------------------------- |
| `--color-brand`            | var lime 500 | "App Green" — primary brand color, website/ad/product                  |
| `--color-brand--highlight` | `#85eb00`    | Brand accent highlight, aligns with website. Bright — use with caution |

---

## Status

Semantic system state. Use in labels, icons, filters, alerts.

| Token                            | Value         | Use for                                        |
| -------------------------------- | ------------- | ---------------------------------------------- |
| `--color-critical`               | red 600       | Action required; user must see to be unblocked |
| `--color-critical--surface`      | red 200       | Background of critical status pill             |
| `--color-critical--onSurface`    | red 800       | Text/icon on critical surface                  |
| `--color-warning`                | yellow 400    | Action _may_ be required                       |
| `--color-warning--surface`       | yellow 200    | Background of warning pill                     |
| `--color-warning--onSurface`     | yellow 700    | Text/icon on warning surface                   |
| `--color-success`                | green 600     | Action completed, no action required           |
| `--color-success--surface`       | green 200     | Background of success pill                     |
| `--color-success--onSurface`     | green 800     | Text/icon on success surface                   |
| `--color-informative`            | lightBlue 500 | Helpful to know, no action required            |
| `--color-informative--surface`   | lightBlue 200 | Background of informative pill                 |
| `--color-informative--onSurface` | lightBlue 700 | Text/icon on informative surface               |
| `--color-inactive`               | blue 700      | Not part of active workflow                    |
| `--color-inactive--surface`      | blue 200      | Background of inactive pill                    |
| `--color-inactive--onSurface`    | blue 900      | Text/icon on inactive surface                  |

---

## Button & Interactions

Buttons and form controls communicate the presence and meaning of interaction. For filled buttons, pair the interactive color with `--color-surface` text so the label matches the app background.

| Token                                            | Value     | Use for                                                            |
| ------------------------------------------------ | --------- | ------------------------------------------------------------------ |
| `--color-interactive`                            | green 600 | Default interactive/CTA color                                      |
| `--color-interactive--hover`                     | green 700 | Hover state of interactive                                         |
| `--color-interactive--subtle`                    | blue 800  | Less pronounced interactive (secondary/dismiss buttons, nav icons) |
| `--color-interactive--subtle--hover`             | blue 900  | Hover of subtle interactive                                        |
| `--color-interactive--background`                | taupe 300 | Background of interactive elements (separates from surface)        |
| `--color-interactive--background--hover`         | taupe 400 | Hover of interactive background                                    |
| `--color-interactive--background--subtle--hover` | green 200 | Subtle interactive background hover                                |
| `--color-destructive`                            | red 600   | Interaction will destroy data/workflow                             |
| `--color-destructive--hover`                     | red 700   | Hover of destructive                                               |
| `--color-disabled`                               | grey 500  | Disabled interactive element                                       |
| `--color-disabled--secondary`                    | grey 200  | Second color for disabled (e.g. bg + label)                        |
| `--color-focus`                                  | blue 500  | Focus ring via `--shadow-focus`. Avoid using directly on UI        |

---

## Utility

Supporting tokens used across components.

| Token                     | Value     | Use for                                           |
| ------------------------- | --------- | ------------------------------------------------- |
| `--color-overlay`         | black 32% | Mask area behind Modals, built-in opacity         |
| `--color-overlay--dimmed` | white 60% | Mask to indicate inactivity (waiting for updates) |
| `--color-white`           | white     | Pure white surface                                |
| `--color-black`           | black     | Pure black                                        |

---

## Background

Surfaces are the background color of almost every element. (Our app calls these "Surfaces").

| Token                                        | Value     | Use for                                                    |
| -------------------------------------------- | --------- | ---------------------------------------------------------- |
| `--color-surface`                            | white     | Default element surface (cards, buttons, inputs)           |
| `--color-surface--hover`                     | taupe 200 | Hover state of an interactive surface                      |
| `--color-surface--active`                    | taupe 300 | Active/pressed state of a surface                          |
| `--color-surface--reverse`                   | blue 900  | Strong-contrast reversed surface (e.g. dark header/footer) |
| `--color-surface--background`                | taupe 200 | Slightly darker app/page background — receded elements     |
| `--color-surface--background--hover`         | taupe 300 | Hover of page background surfaces                          |
| `--color-surface--background--subtle`        | taupe 100 | Background distinct from main surface, but not too receded |
| `--color-surface--background--subtle--hover` | taupe 300 | Hover of subtle background surfaces                        |
| `--color-text--reverse` accent pairing       | —         | Text gets a dedicated reversed variant (see Text)          |

---

## Text

| Token                                 | Value    | Use for                                                   |
| ------------------------------------- | -------- | --------------------------------------------------------- |
| `--color-text`                        | blue 800 | Default body text                                         |
| `--color-text--secondary`             | blue 700 | Less important body text (only with primary text present) |
| `--color-text--reverse`               | white    | Text on reversed/dark surfaces                            |
| `--color-text--reverse--secondary`    | blue 300 | Secondary text on reversed surfaces                       |
| `--field--placeholder-color` _(dark)_ | blue 400 | Input placeholder text                                    |

---

## Heading

| Token             | Value    | Use for                                               |
| ----------------- | -------- | ----------------------------------------------------- |
| `--color-heading` | blue 900 | Bold, high-contrast heading color (cements hierarchy) |

---

## Border

Subtle maintainers of layout structure, defining edges on the same elevation plane.

| Token                            | Value    | Use for                                                   |
| -------------------------------- | -------- | --------------------------------------------------------- |
| `--color-border`                 | blue 300 | Default border — subtle definition between elements       |
| `--color-border--interactive`    | blue 300 | Borders of interactive elements — accessible contrast     |
| `--color-border--section`        | blue 900 | Further sectioning (table headers, list section dividers) |
| `--field--border-color` _(dark)_ | blue 500 | Form field border in dark mode                            |

---

## Workflow (Product statuses)

This App's home-service workflow colors — central to the product. Use sparingly, only on elements directly related to the workflow

| Token                         | Value                | Meaning / use for                                     |
| ----------------------------- | -------------------- | ----------------------------------------------------- |
| `--color-request`             | orange 600           | Requests & assessments — "warm handoff" from consumer |
| `--color-request--surface`    | orange 200           | Request pill background                               |
| `--color-request--onSurface`  | orange 800           | Text/icon on request surface                          |
| `--color-quote`               | pink 700             | Quotes — likelihood of winning work is getting warm   |
| `--color-quote--surface`      | pink 200             | Quote pill background                                 |
| `--color-quote--onSurface`    | pink 800             | Text/icon on quote surface                            |
| `--color-job`                 | green 600            | Jobs — core                                           |
| `--color-job--surface`        | green 200            | Job pill background                                   |
| `--color-job--onSurface`      | green 700            | Text/icon on job surface                              |
| `--color-visit`               | = job                | Visits inherit the job color (closely related)        |
| `--color-visit--surface`      | = job--surface       | Visit pill background                                 |
| `--color-visit--onSurface`    | = job--onSurface     | Text/icon on visit surface                            |
| `--color-invoice`             | lightBlue 700        | Invoices — blue = banking/finance                     |
| `--color-invoice--surface`    | lightBlue 200        | Invoice pill background                               |
| `--color-invoice--onSurface`  | lightBlue 800        | Text/icon on invoice surface                          |
| `--color-payments`            | = invoice            | Payments inherit the invoice color                    |
| `--color-payments--surface`   | = invoice--surface   | Payment pill background                               |
| `--color-payments--onSurface` | = invoice--onSurface | Text/icon on payment surface                          |
| `--color-task`                | lightBlue 800        | Tasks — deeper blue, mostly scheduling                |
| `--color-task--surface`       | blue 200             | Task pill background                                  |
| `--color-task--onSurface`     | blue 800             | Text/icon on task surface                             |
| `--color-event`               | yellow 400           | Events (calendar)                                     |
| `--color-event--surface`      | yellow 200           | Event background                                      |
| `--color-event--onSurface`    | yellow 700           | Text/icon on event surface                            |
| `--color-client`              | taupe 700            | Clients/customers                                     |
| `--color-client--surface`     | taupe 200            | Client pill background                                |
| `--color-client--onSurface`   | taupe 800            | Text/icon on client surface                           |

---

## Icon

| Token                     | Value    | Use for              |
| ------------------------- | -------- | -------------------- |
| `--color-icon`            | blue 800 | Default icon color   |
| `--color-icon--secondary` | blue 500 | Less important icons |

---

## Data Visualization

Charts & categorical data.

| Token                                     | Value      | Use for                      |
| ----------------------------------------- | ---------- | ---------------------------- |
| `--color-dataViz--categorical--1`         | purple 700 | Category 1 series            |
| `--color-dataViz--categorical--2`         | teal 500   | Category 2 series            |
| `--color-dataViz--categorical--3`         | orange 500 | Category 3 series            |
| `--color-dataViz--categorical--1--subtle` | purple 500 | Subtle variant of category 1 |
| `--color-dataViz--categorical--1--bold`   | purple 800 | Bold variant of category 1   |

---

## Legacy named palette (aliases)

These are the pre-semantic-era color names still exposed in `token.css`. They alias into `--color-base-*`. Atlantis recommends the semantic tokens above over these. Each color has the variants: `--light`, `--lighter`, `--lightest`, `--dark`.

| Family             | Base value    | Family                | Base value    |
| ------------------ | ------------- | --------------------- | ------------- |
| `--color-grey`     | grey 400      | `--color-blue`        | blue 900      |
| `--color-white`    | white         | `--color-black`       | black         |
| `--color-taupe`    | taupe 200     | `--color-green`       | green 600     |
| `--color-lime`     | lime 500      | `--color-yellowGreen` | lime 500      |
| `--color-yellow`   | yellow 400    | `--color-red`         | red 600       |
| `--color-greyBlue` | blue 600      | `--color-lightBlue`   | lightBlue 500 |
| `--color-purple`   | pink 800      | `--color-pink`        | pink 600      |
| `--color-orange`   | orange 500    | `--color-brown`       | orange 700    |
| `--color-navy`     | lightBlue 700 | `--color-teal`        | teal 500      |
| `--color-indigo`   | fixed hexes   |                       |               |

> Note: This App's `--color-purple` surprising — it alias to **pink** 800, not base-purple. `--color-green` (etc.) are the legacy names that the semantic system explicitly replaced (e.g. `--color-green` → `--color-interactive`).

---

## Base palette (primitives)

Raw 100→1000 ramps per hue. **Never use directly** — they don't respond to theming. `100` = lightest, `1000` = darkest. Each scale requires no "usage" — it exists to power the semantic layer above.

Scales in `token.css`: `grey`, `taupe`, `red`, `green`, `blue`, `yellow`, `lime`, `lightBlue`, `pink`, `orange`, `teal`, `purple` — each `--100` through `--1000`, plus:

| Token                | Value |
| -------------------- | ----- |
| `--color-base-white` | white |
| `--color-base-black` | black |

---

## Dark theme overrides

In `:root[data-theme="dark"]` the palette _itself_ is remapped — blue 700–1000 get lighter, and every semantic token points to darker surfaces + lighter text:

- `--color-surface` → **needs** blue 900; `--color-surface--background` → blue 1000
- `--color-text` / `--color-heading` → light blue 100–200 (light text on dark)
- Status surfaces swap to the **dark 800–900** step, `--onSurface` swaps to the **300** step
- `--color-interactive` becomes brand lime `#8acc33`; focus/border brighten

---

## Quick decision map ("which variable do I use?")

| I'm styling…                          | use                                                             |
| ------------------------------------- | --------------------------------------------------------------- | --------- | ------------------------------------- |
| A card / modal / list item background | `--color-surface`                                               |
| The whole page background             | `--color-surface--background`                                   |
| Body text                             | `--color-text`                                                  |
| A title/heading                       | `--color-heading`                                               |
| A primary button                      | `--color-interactive`                                           |
| A danger/delete button                | `--color-destructive`                                           |
| A disabled element                    | `--color-disabled` (+`--color-disabled--secondary` for 2-color) |
| Hairline between cards                | `--color-border`                                                |
| Dividers in tables/lists              | `--color-border--section`                                       |
| Success / warning / error badge       | `--color-success                                                | --warning | --critical`+`--surface`+`--onSurface` |
| Job / Quote / Visit / Invoice pills   | the matching workflow token                                     |
| Chart colors                          | `--color-dataViz--categorical--*`                               |
| Dark text on colored bg               | trust the `--onSurface` of that color                           |

## Prohibited

- No raw hex/rgb values in component code — always use design tokens
- No brand text color for long-form paragraphs
- No brand/accent backgrounds for large layout surfaces (pages, sections) unless it's a hero/campaign area
- No manual light/dark value swapping — let the CSS custom properties handle it

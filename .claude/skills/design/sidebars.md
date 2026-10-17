# Sidebar

> Dependencies: `colors.md`, `icon-shapes.md`, `typography.md`

## Core Specs

- Width 248; background `--color-surface`; 1px right border `--color-border`; padding 16 12; group gap 20.

## Anatomy

- **Business switcher:** 32 logo tile (`--color-interactive`, white letter 15/700), business name 14/700 over
  role 12 quiet, chevrons-up-down icon.
- **Groups:** uppercase label 11/600, 0.8 letter-spacing, quiet colour, padding 0 8 6. Order: Home, Schedule,
  Inbox · Work: Requests, Quotes, Jobs, Invoices · Customers: Clients, Pipeline · Grow: Marketing, Reviews,
  Reports · Team: Timesheets, Files. Settings sits at the bottom.
- **Item:** height 36, padding 0 8, gap 10, radius 8; 24 tile in the page's colour (`colors.md`); label 14/500
  `--color-text`; optional count chip (11/700 quiet on `--color-surface--background`, full radius).

## States

| State | Look |
|---|---|
| Hover | Background `--color-surface--hover` |
| Current page | Background `--color-surface--active`; solid tile with a white icon; label 600 `--color-heading` |

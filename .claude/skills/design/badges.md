# Status Pill

> Dependencies: `colors.md`, `radius.md`

## Core Specs

- Radius full; padding 3 10; gap 6.
- 6px dot in the status main colour; text 12/600 in `--onSurface`; background `--surface`.

## Variants

Done `--color-success`, Waiting `--color-warning`, Act now `--color-critical`, Planned `--color-informative`,
Draft `--color-inactive`; record pills use the record family (e.g. `--color-request`).

## Rules

- Words always say the status ("Overdue"), never colour alone.
- In lists and tables pills sit in a fixed-width column so they line up.

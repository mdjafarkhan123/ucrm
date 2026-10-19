# Status Pill

> Dependencies: `colors.md`, `radius.md`

## Core Specs

- Radius full; padding 5 11 (24 high); gap 6.
- 6px dot in the status main colour; text 12/600 in `--onSurface`; background `--surface`.

## Variants

Done `--color-success`, Waiting `--color-warning`, Act now `--color-critical`, Planned `--color-informative`,
Draft `--color-inactive`; record pills use the record family (e.g. `--color-request`).

## Kinds

- **Without a dot:** a plain tinted pill for counts and facts ("3 visits", "Deposit paid").
- **Plain label:** no status; `--color-inactive--surface` with `--color-heading` text ("Residential").
- **Small:** padding 3 9, 5px dot, 11/600, for tight spots.

## Rules

- Words always say the status ("Overdue"), never colour alone.
- In lists and tables pills sit in a fixed-width column so they line up.

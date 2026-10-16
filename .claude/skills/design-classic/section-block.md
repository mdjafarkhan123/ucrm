# Section Block

> Dependencies: `colors.md`, `radius.md`, `borders.md`, `typography.md`, `layout.md`

The house pattern for any titled block, section, or part of a page: a bordered container whose title sits
**on** the top border line, breaking it. Component: `src/lib/components/layout/SectionBlock.svelte`.

## Use it for

Every titled block inside a page or card — form groups, grouped settings, panels in a right rail, grouped
data on a detail page. A block whose title is separate from its container is off-pattern.

A plain `Card` still fits an untitled surface, and `PageHeader` still owns the page's own `h1`.

**Right rails and side panels keep the plain `Card` treatment** — title inside the card, no border notch.
Jafar settled this on the client create/edit form: the border-notch style belongs to the main column, and the
rail reads as a stack of separate cards beside it. `src/lib/components/clients/ClientForm.svelte` is the
reference for both halves.

## Semantics

The tag follows the content, and the component picks it from one prop:

| Content inside          | Prop     | Renders                    |
| ----------------------- | -------- | -------------------------- |
| Form controls           | `form`   | `<fieldset>` + `<legend>`  |
| Anything else           | default  | `<section>` + `h2`/`h3`/`h4` |

`fieldset` is only correct around form controls; a titled panel of read-only data uses the section form,
which reproduces the same look with an absolutely positioned heading.

## Core Specs

- **Border:** `var(--border-base)` solid `var(--color-border)`
- **Radius:** `var(--radius-base)` (8px)
- **Padding:** `var(--space-large)` (24px); `var(--space-base)` (16px) below 768px
- **Inner gap:** `var(--space-base)` (16px), flex column
- **Top margin:** `var(--space-slim)` (12px) — clearance for the title on the border line
- **Title:** `--typography--fontSize-large`, weight 700, `var(--color-heading)`, `lineHeight-tight`
- **Icon:** optional Tabler icon 18×18px in `var(--color-icon--secondary)`, `var(--space-small)` before the text
- **Hint:** optional line under the title, `--typography--fontSize-small`, `var(--color-text--secondary)`

## Variants

- `plain` (default) — transparent, sits on whatever surface holds it
- `filled` — `var(--color-surface--background)`, for the block carrying the primary content

## Actions

An optional `actions` snippet sits on the top border at the right, mirroring the title. Use it for a single
control that belongs to the block, such as an Add button.

**Keep it a labelled text button, not a bare icon.** Jafar weighed an icon-only affordance on 2026-08-17 and
rejected it himself: the clickable-icon pattern only exists inside an `EmptyState`, so it disappears the
moment the block has content, leaving nowhere to add the second record. A control on the border line stays in
the same place whether the block is empty or full, which is also what Jobber does.

## The notch

The title and actions paint over the border with `--section-block-notch`, which defaults to
`var(--color-surface)`. When the block sits on a different background, set that variable on the block or an
ancestor so the notch matches what is behind it:

```scss
.settings-page {
	--section-block-notch: var(--color-surface--background);
}
```

## Rules

- Reach for `SectionBlock` before writing a bordered-and-titled container by hand.
- Pass `form` whenever the block contains inputs.
- Pass `level` so the heading follows the page's hierarchy; never skip a level.
- Keep the title a short noun phrase — it sits on a border line and truncates with an ellipsis.
- The notch background must match the surface behind the block, or the border shows through the title.

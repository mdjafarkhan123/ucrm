# Typography

> Dependencies: `colors.md`

## Core Rules

- **Font family (body):** `--typography--fontFamily-normal` — `Inter, Helvetica, Arial, sans-serif`. Configured at app level, never override in a component.
- **Display family:** `--typography--fontFamily-display` — reserved for display weights (800–900), i.e. level-1 page titles. Falls back to `Poppins` where the licensed face is unavailable.
- **Base font-size:** `--typography--fontSize-base` (14px). This is the web floor — the smallest easily readable size.
- **Headings:** level 1 → weight 900, levels 2–6 → weight 700. Heading text always `var(--color-heading)`.
- **Body copy:** `var(--color-text)`. Never use a brand/status color for paragraphs longer than one sentence.
- **Semantic HTML:** Use `h1`–`h6` in order, never skip levels. `element` may override the rendered tag (e.g. an `h4` that renders as `<h2>`) when document structure requires it.

## Type Scale (web tokens)

| Token                           | Size |
| ------------------------------- | ---- |
| `--typography--fontSize-smaller` | 10px |
| `--typography--fontSize-small`   | 12px |
| `--typography--fontSize-base`    | 14px |
| `--typography--fontSize-large`   | 16px |
| `--typography--fontSize-larger`  | 20px |
| `--typography--fontSize-largest` | 24px |
| `--typography--fontSize-jumbo`   | 36px |
| `--typography--fontSize-extravagant` | 48px |

Line-heights are frozen per size — never mixed:

| Size                            | Line-height token                  | Value |
| ------------------------------- | ---------------------------------- | ----- |
| `smaller` (10px)                | `--typography--lineHeight-tight`   | 1.2   |
| `small` (12px)                  | `--typography--lineHeight-tighter` | 1.143 |
| `base` (14px)                   | `--typography--lineHeight-base`    | 1.25  |
| `large` (16px)                  | `--typography--lineHeight-large`   | 1.34  |
| `larger` (20px)                 | `--typography--lineHeight-tight`   | 1.2   |
| `largest` (24px)                | `--typography--lineHeight-tightest`| 1.12  |
| `jumbo` (36px)                  | `--typography--lineHeight-minuscule` | 1.08 |
| `extravagant` (48px)            | `--typography--lineHeight-minuscule` | 1.08 |

Letter-spacing defaults to `--typography--letterSpacing-base` (0). The `--typography--letterSpacing-loose` (0.4) token is only for uppercase micro-labels.

## Heading Scale

Each level maps to a fixed size/weight pair — no other presets exist:

| Element | Size token         | Size | Weight          | Family       | Line-height | Case |
| ------- | ------------------ | ---- | --------------- | ------------ | ----------- | ---- |
| `h1`    | `jumbo`            | 36px | 900 (`black`)    | display     | 1.08        | —    |
| `h2`    | `largest`          | 24px | 700 (`bold`)     | normal      | 1.12        | —    |
| `h3`    | `larger`           | 20px | 700 (`bold`)     | normal      | 1.2         | —    |
| `h4`    | `large`            | 16px | 700 (`bold`)     | normal      | 1.34        | —    |
| `h5`    | `base`             | 14px | 700 (`bold`)     | normal      | 1.25        | —    |
| `h6`    | `small`            | 12px | 700 (`bold`)     | normal      | 1.143        | uppercase (eyebrow) |

- **h1** — exactly one per page, the page title.
- **h2** — large content groups; may be skipped if the page has no such group.
- **h3** — groups content/forms on one subject.
- **h4** — groups content inside a card or below an h3.
- **h5** — groups content below an h4.
- **h6** — eyebrow pattern: small uppercase label grouping small lists/content. Sentence case is used everywhere else.

**Headings carry no default margins** — the typography base resets `margin`/`padding` to 0. Vertical rhythm comes entirely from the layout primitives (Content / Stack / spacing tokens), not from the heading itself. So spacing lives outside the heading.

## Responsive

Sizes are locked per breakpoint via the token system — only the three display sizes scale down at narrow widths (`≤639px`):

| Level | Desktop | ≤639px |
| ----- | ------- | ------ |
| `h1`  | 36px    | 28px   |
| `h2`  | 24px    | 22px   |
| `h3`  | 20px    | 20px   |
| `h4`  | 16px    | 16px   |
| `h5`  | 14px    | 14px   |
| `h6`  | 12px    | 12px   |

The tight line-heights (1.08–1.25) are intentional at display sizes. If you must thin a line, never go below the `minuscule` 1.08 token.

## Paragraphs (Text component)

Three scale sizes only — there is no "leading paragraph" or larger prose tier:

- **Base (default body):** `--typography--fontSize-base` (14px), weight 400, `var(--color-text)`, line-height `--typography--lineHeight-base` (1.25). Default for almost all paragraphs.
- **Large (emphasis / lead):** `--typography--fontSize-large` (16px), weight 400, `var(--color-text)`, line-height `--typography--lineHeight-large` (1.34).
- **Supporting context:** `--typography--fontSize-base` (14px), weight 400, `var(--color-text)`, line-height `--typography--lineHeight-base` (1.25). Supporting copy under KPI values and other primary content.
- **Small (metadata):** `--typography--fontSize-small` (12px), weight 400, `var(--color-text)`, line-height `--typography--lineHeight-tighter` (1.143). Helper text, captions, and metadata.

**Subdued:** a `subdued` variation exists — same sizes, `var(--color-text--secondary)`. Use it to de-emphasize less-important copy. Keep supporting text to 1–2 short sentences.

**Status variations** (message/feedback text only): `success` → `--color-success`, `error` → `--color-critical`, `warn` → `--color-warning`, `info` → `--color-informative`, `disabled` → `--color-disabled`.

**Alignment:** left by default. Right-align only when a label helps keep columns aligned; center only in standalone/empty states.

## UI Labels

| Context                    | Size         | Weight       |
| -------------------------- | ------------ | ------------ |
| Button labels (base size)  | `--typography--fontSize-base` (14px) | 600 (`semiBold`) |
| Button labels (large size) | `--typography--fontSize-large` (16px) | 600 (`semiBold`) |
| Field / input labels       | `--typography--fontSize-base` (14px) | 400 — none     |
| Mini (floating) field label | `--typography--fontSize-small` (12px) | 400 — none  |
| Captions / meta            | `--typography--fontSize-small` (12px) | 400 — none |

Do not apply paragraph line-heights (1.34 / 1.25) to control labels; they render at the size token's own line-height.

## Links

- **Color:** `var(--color-interactive)`
- **Underline:** always underlined — there is no "remove underline on hover". `text-underline-offset` is `var(--space-smaller)` (4px), thickness 1px.
- **Hover/focus:** `var(--color-interactive--hover)` — both the text color and the underline color switch to the hover green.
- **Focus-visible:** `--shadow-focus` focus ring.
- **External links:** open in a new tab (`target="_blank"`, `rel="noopener noreferrer"`).
- Use `Link` (renders an `<a>`), never a Button, for navigation. Link text should describe the destination — not "click here".

## Emphasis

- **Bold (`<strong>`):** call out strong importance / urgency. Weight 700.
- **Italic (`<em>`):** stress emphasis that changes the meaning of a word — tone, not visual hierarchy.
- **Highlight:** a hand-drawn marker-underline effect (an `SVG` stroke in brand lime), keeping the surrounding typeface and weight. Only for page titles/subtitles, sparingly.
- **All-caps:** only for short micro-labels — the `h6` eyebrow or explicit block level: 12px uppercase, `--typography--letterSpacing-loose` (0.4). Never for sentence-case body.

## Dark Mode

Hierarchy stays identical. Only color tokens change (automatic via CSS custom properties) — `--color-heading`, `--color-text`, `--color-text--secondary`, statuses, and `--color-interactive*` all flip `[data-theme="dark"]`. Sizes, weights, and spacing remain constant.

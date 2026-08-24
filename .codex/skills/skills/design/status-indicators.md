# Status Indicators

Dependencies: `colors.md`, `badges.md`, `radius.md`

Status indicators communicate the state of an item with a small colored dot. A
status label combines that dot with a short text label.

## Available statuses

Only these five statuses are supported:

| Status | Meaning | Indicator token | Surface token | Text token |
|---|---|---|---|---|
| Success | The item is in a successful state, such as approved or paid. | `var(--color-success)` | `var(--color-success--surface)` | `var(--color-success--onSurface)` |
| Critical | The item needs urgent attention, such as an overdue payment. | `var(--color-critical)` | `var(--color-critical--surface)` | `var(--color-critical--onSurface)` |
| Warning | A potential issue may require attention, such as an upcoming deadline. | `var(--color-warning)` | `var(--color-warning--surface)` | `var(--color-warning--onSurface)` |
| Informative | The state is useful to know but may not require action. | `var(--color-informative)` | `var(--color-informative--surface)` | `var(--color-informative--onSurface)` |
| Inactive | The item is archived, closed, or outside the active workflow. | `var(--color-inactive)` | `var(--color-inactive--surface)` | `var(--color-inactive--onSurface)` |

Do not add status colors outside this set. Theme changes are handled by the
semantic tokens.

## Status indicator

Use the indicator when a nearby label or other content already explains the
state. It is purely visual and must not be the only way the status is conveyed.

```css
.status-indicator {
  display: inline-block;
  width: 8px;
  height: 8px;
  flex-shrink: 0;
  border-radius: 50%;
  background-color: var(--color-success);
}
```

Set `background-color` to the matching indicator token for the selected status.
The indicator is always an 8px × 8px circle.

The indicator accepts one required `status` value: `success`, `critical`,
`warning`, `informative`, or `inactive`.

## Status label

Use the labeled form when the status needs to be understandable without relying
on color. The label has `role="status"`, contains a short text label, and places
the indicator beside the text.

```css
.status-label {
  display: flex;
  width: fit-content;
  flex-flow: row nowrap;
  gap: 6px;
  padding: 6px 10px 6px 8px;
  border-radius: 12px;
  background-color: var(--color-success--surface);
}

.status-label__text {
  color: var(--color-success--onSurface);
  font-size: var(--typography--fontSize-small);
  line-height: 1;
}
```

The status label uses:

- 8px indicator diameter;
- 6px top and bottom padding;
- 8px leading padding and 10px trailing padding;
- 6px gap between the indicator and label;
- 12px corner radius;
- small typography (`var(--typography--fontSize-small)`);
- a 1 line-height for a reliable 24px total height.

Apply the matching surface and on-surface tokens from the status table to the
label background and text. Do not add a border.

### Alignment

The default alignment places the indicator before the label. For layouts where
the label is aligned to the opposite edge, reverse the row so the indicator
follows the text:

```css
.status-label--end {
  flex-direction: row-reverse;
}
```

The component should hug its contents and may grow as needed. Labels should be
short, ideally no longer than two words.

The label text is required. Alignment defaults to `start`; status defaults to
`inactive` when no status is supplied. The supported alignment values are
`start` and `end`.

## Usage rules

- Use the labeled form for status communication in lists, tables, cards, and detail views.
- Keep the text label readable by assistive technology; color is reinforcement only.
- Use `success`, `critical`, `warning`, `informative`, or `inactive` directly as the state variant.
- Use the corresponding `--surface` token for the label background and `--onSurface` token for its text.
- Keep the indicator before the text unless the layout explicitly uses end alignment.
- Do not use a status label for counts, trends, tags, or general metadata; use the appropriate inline label pattern instead.

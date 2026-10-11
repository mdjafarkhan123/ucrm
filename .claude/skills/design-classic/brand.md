# Brand

## Identity

- **Design system name:** UpliftContractor
- **Project name:** UCrm
- **Primary color:** `var(--color-brand)`
- **Project logo:** Update this file with the logo URL once set.

## Brand Voice

Professional, reliable, and efficient. This tool is trusted on the job site. The
design reflects clarity over complexity — contractors need answers fast, not
decoration.

## Brand Tokens

Use semantic tokens so branding responds correctly to the active theme.

| Token | Purpose |
| --- | --- |
| `var(--color-brand)` | Primary brand color for actions, links, active states, and key data highlights |
| `var(--color-brand--highlight)` | Bright accent for small emphasis details and decorative highlights |
| `var(--color-interactive)` | Default interactive and primary action color |
| `var(--color-interactive--hover)` | Hover state for interactive elements |
| `var(--color-surface)` | Text and icons placed on interactive brand backgrounds |
| `var(--typography--fontFamily-display)` | Display typeface for prominent branded headings |
| `var(--typography--fontFamily-normal)` | Body copy, labels, navigation, and fallback text mark treatment |

## Logo Usage

- Use the logo in the sidebar header, login/auth screens, empty states, and branded report headers.
- Maintain clear space around the logo equal to one quarter of the logo height.
- Never crop, recolor, rotate, or place it on a low-contrast background.
- If no logo is set, use a text mark with “Contractor CRM” in a semibold normal typeface and `var(--color-brand)`.

## Rules

- Pair the logo with an accessible text label where the mark alone would be ambiguous.
- Never use `var(--color-brand)` for long-form body paragraphs.
- Never use brand backgrounds for large layout surfaces such as the sidebar fill or full-page backgrounds.
- Use `var(--color-brand--highlight)` sparingly and only for small emphasis details.
- Use `var(--color-interactive)` and `var(--color-interactive--hover)` for primary actions and their states.
- Let semantic tokens handle light and dark themes; do not manually swap brand values.
- Use `colors.md`, `typography.md`, `layout.md`, and component modules for all other visual values.

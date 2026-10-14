# Section Block

Component: src/lib/components/layout/SectionBlock.svelte.

Use SectionBlock for a titled section, form group, panel or grouped data on a Classic page. Use PageHeader for the page h1 and RailCard for a titled card in a right rail.

## Semantics

- Pass form for controls. It renders a fieldset and legend.
- Otherwise it renders a section with an h2, h3 or h4 selected by level.
- Pass level so headings follow the page hierarchy.

## Classic appearance

SectionBlock is a card in the Classic redesign. Both plain and filled variants use classic2-surface, a 1px classic2-border, 20px corners and the card shadow in the design recipe. The title sits inside the card. The old border notch is not part of the current Classic look.

- Desktop padding: 24px; phone padding: 16px
- Inner gap: 16px
- Title: 16px, 700, classic2-ink
- Hint: 12px classic2-muted
- Optional actions sit at the top right inside the card; leave room for them beside the title
- Keep the card surface and shadow from docs/classic-theme-redesign-design-recipe.md in light and dark modes

## Content

Keep the title a short noun phrase. Use an actions snippet for a labeled control that belongs to the section, such as adding a record. Preserve current save, validation and permission behavior.

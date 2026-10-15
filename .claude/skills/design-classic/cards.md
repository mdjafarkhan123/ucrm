# Cards

Classic card surfaces use the approved classic2 palette and the shared B3 components.

## Appearance

- Surface: classic2-surface
- Border: classic2-border, 1px
- Corners: 20px
- Shadow: classic2-shadow-near at 0 1px 2px and classic2-shadow-far at 0 10px 28px
- Heading: classic2-ink; keep the page heading hierarchy intact

The exact light and dark values are in docs/classic-theme-redesign-design-recipe.md.

## Components

- Use ui/Card for a plain card with optional heading.
- Use layout/SectionBlock for titled sections and groups of form controls.
- Use layout/RailCard for titled cards in a right rail.
- On a rebuilt Classic record page, use layout/RecordCard (`size="main"` or `"rail"`) for the classic.pen
  record cards: title, optional count chip and subtitle, actions, edge-to-edge rows and an optional footer.
  Shared Notes and Photos and files take `look="record"` there (NotesPanel, RecordFilesCard); every other page
  keeps their default look until its own redesign opts in.

SectionBlock and RailCard keep their own padding and heading rules in their modules. A static card has no hover effect. Interactive actions keep their hover and focus states on the action itself.

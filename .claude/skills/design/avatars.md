# Avatars

> Dependencies: `colors.md`, `radius.md`, `shadows.md`

## Core Specs

- A circle showing the person's photo, or their initials on a soft colour.
- Sizes and initials: 24 (12), 32 (12), 40 (14), 44 (14), 64 (20); initials 600, letter-spacing -0.2 from 40 up.
- Colour: one of eight families picked from the person's id: critical, request, success, conversation,
  inactive, growth, quote, job. Fill `--color-<family>--surface`, initials `--color-<family>--onSurface`.
- A 2px `--color-surface` ring keeps an avatar crisp on chips, cards and photos.
- Photo: fills the circle, keeps the white ring, shadow 0 1 3 `--color-heading` at 14%.

## In use

- List row: 32 avatar at the left of the row, 12 gap to the name; an assignee at the right is a 24 avatar, 8 after
  the name.
- People pick chips: see `inputs.md`.

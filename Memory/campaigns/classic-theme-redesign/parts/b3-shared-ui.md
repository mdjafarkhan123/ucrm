# B3 — shared Classic cards and controls

**Stage:** In progress, checkpoint 2026-10-14. **Plan:** `docs/classic-theme-redesign-behavior-contract.md` and `docs/classic-theme-redesign-design-recipe.md`. **Branch/worktree:** `codex/classic-b3`, `/home/jafar/Ucrm/.worktrees/classic-b3`, based on `ed18f953`. **Reservation:** `787beb2d9d99` (`classic-theme-redesign/b3-shared-ui`).

## Current state

No B3 source files have been changed. The approved B1 token foundation is already integrated: `ClassicFrame.svelte` installs the approved `classic2-*` tokens on the document root while Classic is selected, including for portalled menus and dialogs. Shared controls and layout components still style themselves with older generic variables such as `--color-*` and `--space-*`. The application is therefore mixed today: B2's shell uses the new Classic look; shared cards and controls still have their older styling. B3 must make those components consume the approved Classic values and preserve the Botanical appearance.

The active `crm-design-system` A2a work is a separate Appearance chooser/notice demo. It is not the token foundation and does not block B3.

## Steps

1. Read the B3 sections of the behavior contract and design recipe, then the Classic design modules for cards, section blocks, buttons, inputs, badges and grouped controls.
2. Inspect the approved Classic Pencil parts and the existing components before editing.
3. Choose a Classic-only way to connect the existing component styles to `classic2-*`; keep global `app.scss` as the baseline and do not alter Botanical styling.
4. Update the approved shared parts while retaining their current labels, validation, loading/disabled/error behavior, keyboard use and focus behavior.
5. Check representative Classic screens at desktop and phone sizes in light and dark modes, then verify Botanical stays unchanged.

## Proven form guidance

Keep visible labels associated with controls, connect hints and errors to their fields, and make error text specific. References: [W3C labels](https://www.w3.org/WAI/tutorials/forms/labels/), [W3C instructions](https://www.w3.org/WAI/tutorials/forms/instructions/), [GOV.UK text input](https://design-system.service.gov.uk/components/text-input/) and [GOV.UK button](https://design-system.service.gov.uk/components/button/).

## Next

Resume in this worktree. Confirm the exact B3 component list and the Classic-only token connection, then begin component edits. The branch is still unmerged; follow `docs/agent-concurrency.md` when handing over or integrating, and release reservation `787beb2d9d99` only after a safe handoff or integration with this checkpoint updated.

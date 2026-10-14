# B3 — shared Classic cards and controls

**Stage:** In progress — component styling is implemented and the production build passes; the live screen check is still pending. **Plan:** `docs/classic-theme-redesign-behavior-contract.md` and `docs/classic-theme-redesign-design-recipe.md`. **Branch/worktree:** `codex/classic-b3`, `/home/jafar/Ucrm/.worktrees/classic-b3`, based on main merge `96d4cb8d`. **Reservation:** `797a11aa2606` (`codex-classic-b3-continue`).

## Current state

B3 connects the existing shared parts to the approved `classic2-*` design while Classic is selected. It covers `SectionBlock`, `RailCard`, generic `Card`, buttons, inputs, textarea, form labels, selects and their portalled options, status badges, segmented controls, checkboxes, toggles and radio groups. The CSS remains inside component styles and is gated by the active Classic shell; Botanical styling and component behavior were left as before. The Classic design guidance now documents these parts, including the segmented control.

`npx prettier --check` passes for every changed source and guidance file, `git diff --check` passes, and `npx svelte-kit sync && npm run build` succeeds. The build reports an unused CSS selector warning in the existing `JobVisitsSection.svelte`; it does not involve B3.

The live screen check has not been completed. CUA returned no available apps or browsers, and both the in-app browser and Chrome entry points were unavailable. No screen screenshots or journey proof are claimed.

The active `crm-design-system` A2a work is a separate Appearance chooser/notice demo. It is not the token foundation and does not block B3.

## Approved scope and checks

1. Follow the approved B3 recipe and current Classic Pencil parts for cards, section blocks, buttons, inputs, badges and grouped controls.
2. Keep all overrides scoped to the Classic presentation, use the existing `classic2-*` tokens, and preserve Botanical styles.
3. Retain current labels, validation, loading/disabled/error behavior, keyboard use and focus behavior.
4. Before integration, inspect Settings and one other representative page in Classic at desktop and 390px, in light and dark modes; check focus, disabled, error and select-menu states; verify the Botanical preview is unchanged. Record screenshots and prove the main journey once on the live app.

## Proven form guidance

Keep visible labels associated with controls, connect hints and errors to their fields, and make error text specific. References: [W3C labels](https://www.w3.org/WAI/tutorials/forms/labels/), [W3C instructions](https://www.w3.org/WAI/tutorials/forms/instructions/), [GOV.UK text input](https://design-system.service.gov.uk/components/text-input/) and [GOV.UK button](https://design-system.service.gov.uk/components/button/).

## Next

Use a session with a working browser surface to complete the approved screen and journey checks. Keep this branch unmerged until those checks pass, then follow `docs/agent-concurrency.md` for integration.

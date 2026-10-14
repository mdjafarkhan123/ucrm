# B3 — shared Classic cards and controls

**Stage:** Verified on the feature branch; integration pending. **Plan:** `docs/classic-theme-redesign-behavior-contract.md` and `docs/classic-theme-redesign-design-recipe.md`. **Branch/worktree:** `codex/classic-b3`, `/home/jafar/Ucrm/.worktrees/classic-b3`, based on main merge `96d4cb8d`. **Reservation:** `797a11aa2606` (`codex-classic-b3-continue`).

## Current state

B3 connects the existing shared parts to the approved `classic2-*` design while Classic is selected. It covers `SectionBlock`, `RailCard`, generic `Card`, buttons, inputs, textarea, form labels, selects and portalled options, status badges, segmented controls, checkboxes, toggles and radio groups. Dashboard quick actions now use the shared Button; the dark search shortcut label also meets contrast. Botanical keeps the prior Dashboard quick-action and shared Settings styles.

The approved screen check is complete on the running branch app with the existing test account. Settings, Business Profile and a representative Job were checked at desktop and 390px in light and dark. The checks covered form labels, keyboard focus, select open/dismiss, disabled Save, server validation error, phone text at 125%, and mobile navigation open/Escape/focus return/route navigation. The main path through Settings → Business Profile and Jobs → a sample Job was navigated. A client form request returned 422 on the server schema check before database access.

A focused contrast scan on the Dashboard found no small-control contrast failures in light or dark after the shared-button and search-label fixes. Botanical preview computed styles match main for the Dashboard actions and Settings SectionBlock/Button. Screenshots are in `/tmp/classic-b3-*`.

`npx prettier --check`, `git diff --check`, the Svelte autofixer, and `npm run build` pass. Build output includes an existing unused `.job-visits-section` CSS selector warning in `JobVisitsSection.svelte`, outside B3. CUA had no browser surface, so the approved local Playwright route was used for screen checks.

The existing Settings layout still clips content on phone width; that remains in the later Settings stage. The test account did not expose the optional service-area field, so that particular field state was not checked.

The active `crm-design-system` A2a work is a separate Appearance chooser/notice demo. It is not the token foundation and does not block B3.

## Approved scope and checks

1. Follow the approved B3 recipe and current Classic Pencil parts for cards, section blocks, buttons, inputs, badges and grouped controls.
2. Keep all overrides scoped to the Classic presentation, use the existing `classic2-*` tokens, and preserve Botanical styles.
3. Retain current labels, validation, loading/disabled/error behavior, keyboard use and focus behavior.
4. Completed before integration: inspected Settings, Business Profile and a representative Job at desktop and 390px in light and dark; checked focus, disabled, error, select-menu and mobile navigation states; compared Botanical styles; recorded screenshots and navigated the main page journeys.

## Proven form guidance

Keep visible labels associated with controls, connect hints and errors to their fields, and make error text specific. References: [W3C labels](https://www.w3.org/WAI/tutorials/forms/labels/), [W3C instructions](https://www.w3.org/WAI/tutorials/forms/instructions/), [GOV.UK text input](https://design-system.service.gov.uk/components/text-input/) and [GOV.UK button](https://design-system.service.gov.uk/components/button/).

## Next

Commit and push the contrast fixes and this proof note, then integrate the branch from a clean main worktree following `docs/agent-concurrency.md`. B4 Save bar is next after B3 integration.

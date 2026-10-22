# Batch 65 · Branding (Brand studio) — built 2026-10-22

Approved design: Pencil `FjLSw` (A). Page: `src/routes/(app)/settings/branding/+page.svelte`, preview in
`src/lib/components/settings/branding/BrandPreview.svelte`, colour rules in `src/lib/settings/brand-colour.ts`
(unit-tested, 6 tests pass).

Checked live at 1440 on the Raad LTD owner (light and dark) and the finance role.

- `branding-owner-light-1440.png`, `branding-owner-dark-1440.png`: the page as saved.
- `colour-changed-save-bar.png`: a quick pick chosen; floating bar says "1 change not saved".
- `logo-removed-on-save.png`: Remove pressed; paper faded, "Removed on Save" and Undo, bar counts 2 changes.
- `new-logo-website-chat.png`: a picked file shows "Not saved yet"; the Website chat view follows the colour.
- `someone-saved-first.png`: another save landed first; red notice, bar turns red with "See their version".
- `finance-read-only.png`: lock notice, colour code disabled, no Replace/Remove/quick picks/save bar; preview still works.
- Main journey: typed a colour code, pressed Save ("Branding saved."), reloaded and the code stuck; forced a clash,
  Save showed the notice (409), See their version loaded the other colour and cleared the bar; the original
  colour (#339E83) was then typed back and saved.

Differences from the drawing:
- Sample customer pages are drawn by the preview itself (Quote page, Shared files, Website chat); the real customer
  quote page now gets the brand-colour line across its top (`CustomerQuoteDocument.svelte`). The customer
  Approve button and the shared-files page keep their current colours until Jafar says to change them.
- The page description wraps to two lines at 1440 (the shared page header's width).
- Not driven live: the loading skeleton and the "Being checked" logo state (needs a real upload).

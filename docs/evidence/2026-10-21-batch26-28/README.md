# Batches 26–28 — build proof (2026-10-21)

Approved designs: Batch 26 `l62Og` A (email preview pop-up), Batch 27 `DXj9z` A + A (channel pill, communication
settings pop-up), Batch 28 `Y3od0z` B (questions on a public form). Restyle only: same words, fields, writes,
permissions and queries.

## What changed

- `marketing/MarketingTemplatePreviewDialog`, `MarketingTemplatePreview`: Marketing `mail` tile and quiet line in
  the header, no footer; Desktop/Mobile switch with icons (chosen icon in `--color-growth`); the email centred on
  white (600 / 375) in a subtle well; email-shaped loading bone; couldn't-load centred in a bordered box.
- `communications/ComposerChannelMenu`: white raised pill with teal icon and chevron (turns up when open); 216
  menu with teal icons and a green check on the current channel; one channel is the teal look-only pill.
- `ui/DropdownMenu`: two general options, `current` on an item (bold + green check, read out as "current") and
  `contentClass` for a menu's own width. Existing menus unchanged.
- `clients/CommunicationSettingsDialog`: `bell-ringing` header tile and quiet line; group rows (240 left column,
  record-colour tile, hairlines); "Not sending" yellow strip under its tick; Do not disturb / No marketing as
  notice strips (rows at 50% for Do not disturb); consent note with `shield-check`; Done in the footer bar.
- `forms/PublicFormQuestion`: one card per question with an orange number tile (number passed by the caller,
  counted across sections on the public form, by position in the review feedback form); choices as 44 tap tiles;
  pick-one and Yes/No side by side; Yes/No with thumbs tiles (green when picked).

## Screen check

Temporary fixture page (removed before commit) at 1440 in light and dark: every question kind with picked
states; channel pill closed/open/single; settings pop-up in normal, Do not disturb and staff (no-link) states;
preview loading and couldn't-load. Compared with each Pencil board; fixed two differences found (Yes/No had a
radio circle the drawing doesn't have; the "Not sending" strip sat beside its tick instead of under it) and
centred the couldn't-load state. Screenshots in this folder.

## Checks

- Changed components compiled through SCSS + Svelte compiler: 8 files, 0 errors, 0 warnings.
- Svelte MCP autofixer (style blocks removed): no issues on all changed components.
- Full type check and lint deferred to campaign close (Jafar, 2026-10-21).

## Live check (main, public tunnel, 2026-10-21)

Merged as `9ecb2149`. Checked as the Raad LTD owner in Chrome at 1440 light: public form `kitchen-remodel-request`
(numbered card, tile picks; not submitted), inbox reply box channel menu (teal icons, check on Email), a starter
template's email preview (real render, Desktop and Mobile), and Greenfield Property Group's communication
settings (real "Not sending" strip; closed with Done and the edit cancelled, nothing saved). The main dev
server had missed `DropdownMenu.svelte` after the merge; touching the merged files reloaded it.

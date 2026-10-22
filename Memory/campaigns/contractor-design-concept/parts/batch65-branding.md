# Batch 65 · Branding

**Board:** `concept.pen` → "Concept · Batch 65 · Branding · Approved A · 2026-10-22" (`FjLSw`), right of
Batch 64. **Approved A (Brand studio) by Jafar 2026-10-22**; Option B removed from the board. Piece: `(app)/settings/branding` (list-6a). Opened from Branding on the
approved Settings home (Batch 63 A) and the "Logo in Branding" link on Business profile (Batch 64 B).

## Research (what to show, not the look)

- Stripe Branding: logo, brand colour and a live preview of the customer pages (checkout, invoice, receipt).
- Shopify Brand: logo and colours kept together as one brand kit.
- Square invoices: logo and colour previewed on the invoice itself.
- Jobber: logo and colour for the client hub.

## Live behaviour kept (`src/routes/(app)/settings/branding/+page.svelte`)

Upload, replace, remove and undo the logo (PNG, JPG or WEBP up to 2 MB, safety check before it shows); "Not saved
yet" and "Removed when you save" states; colour picker, Reset to default (`#2c5cc5`); Save and Cancel; read-only
staff view with the last editor; someone-saved-first message; leave-page warning.

## Options

- **A · Brand studio** (`Eaypl`, dark `N1Km3h`): improved live page. Left: Logo card (logo on paper, its small
  sizes, Replace and Remove) and Brand colour card (swatch, colour code field, Reset to default, quick picks,
  reads-clearly notice). Right: "What customers see" preview with a switch (Quote page, Shared files, Website chat)
  and a team note about the sidebar. A floating save bar once something changes.
- **B · Brand kit** (`q63AwG`, dark `j31j6w`; open state `hpF3u`): new concept, read first like Business profile B.
  A brand kit card (logo on paper, "Checked and live" pill, a big colour slab with the code, a sample button and
  "White words read clearly", reset and last-change facts) with Edit brand; under it four small pictures of where
  the brand shows (Quote page, Shared files, Website chat, Your sidebar) with who sees it and what it uses. Edit
  brand opens the kit in place with Cancel and Save branding; a "too light" warning is drawn too.

## For the builder / Jafar (new behaviour to approve with the option)

- Quick-pick colours, a typed colour-code field and the readability check (white words on the colour) are new.
- Today the colour reaches only the website chat and the quote's fallback mark; both options show it on the
  customer page's top line and main button. Needs Jafar's yes before the customer pages change.
- After approval: draw the staff view and loading for the chosen option (checklist row asks for both).

## After approval (2026-10-22)

- Drawn: "Logo states" panel `xSOZT` (No logo yet, New logo · Not saved yet, Saved · Being checked, Removed · Undo).
- New behaviour (quick picks, colour-code box, readability check, colour on the customer quote top line and main
  button) is taken as covered by the approval of A, as with Batch 64; confirm with Jafar if the builder is unsure.
- Drawn: staff view `RQL5t` (lock notice, read only, preview kept) and someone-saved-first panel `M4vpJ`
  (critical notice, save bar with See their version). Loading follows Batch 48. Look rules: design `layout.md` §
  Branding.
- **Next:** Jafar's Ctrl+S in Pencil (file last saved 10:46, before the approval edits), then commit
  `concept.pen` from the main checkout copy and merge this branch to main for building.

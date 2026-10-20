# Photos and Files

> Dependencies: `colors.md`, `radius.md`, `buttons.md`, `badges.md`, `icon-shapes.md`

Pencil: `concept.pen` → board "Photos and files" (`b4BxuV`), approved 2026-10-19.

## Photo viewer

- Over a near-black room (black at 88%), the same in light and dark mode. Content sits on the dark, not in a card.
- **Bar on top**, padding 16 20: at the left a glass count capsule (white 12% fill, 1px white 18% edge, pill
  corners, padding 8 14, gap 8: 16 `photos` icon white 80%, then "3 of 8" 13/600 white), 14 apart from the name
  (15/600 white) over the photo's words (13, white 72%).
- At the right, download and close joined in one glass capsule (same fill and edge, padding 4, gap 2): two 36
  round buttons, 18 white icons.
- **Stage:** 44 round arrows (white 12% fill, 20 white chevron) at the sides, 20 from the photo; photo radius 8.
- **Strip**, padding 16 20, thumbs 56×42 radius 6, 8 apart, centred. Other photos at 55% opacity; the one
  showing at full opacity with a 2px `--color-interactive` ring.
- Hover on any glass control: white 20% fill. Focus: `--shadow-focus`.

## File picture

- Grid size: a 4:3 box, radius 8, `--color-surface--background`. A photo fills it (cover).
- **Document:** a small white sheet centred in the box: 64×84, radius 6, 1px `--color-border`, soft shadow
  (0 2 6, heading at 8%), a folded top-right corner (18) in `--color-surface--background--subtle`, three grey
  text lines (`--color-border`, 3 high), and a type tab hanging off its left edge: radius 4, padding 2 6,
  10/700 white, letter-spacing 0.4, filled in the file family's colour (`colors.md` → File families).
- **Still being checked:** the whole box `--color-warning--surface`; centred a 40 white tile (radius 10) with a
  20 `clock` in `--color-warning`, then "Still being checked" 12/600 `--color-warning--onSurface`, 8 apart.
- **Upload failed / blocked:** the same in `--color-critical` (`alert-triangle`, "Upload failed" or "Blocked by
  the virus scan").
- **List line (40):** radius 8; a photo fills it; a document is a 24×30 sheet with a small type tab; still being
  checked is a `--color-warning--surface` square with an 18 `clock`.
- **Details panel:** the box 200 high, the sheet 104×136 (radius 8) with a 12/700 type tab.

## Photo box

- Fills the size the caller gives; radius 8.
- **Empty:** `--color-surface--background--subtle`, 1.5px dashed `--color-border--interactive--hover` edge;
  centred a 22 `photo-plus` in `--color-interactive` over "Add photo" 13/600 `--color-heading`, 8 apart.
- Hover: fill `--color-surface--hover`, dashes, icon and label `--color-interactive--hover`. Focus:
  `--shadow-focus`. Disabled: `--color-disabled--secondary` fill, icon, dashes and label `--color-disabled`.
- **Uploading:** solid 1px `--color-border` edge, a 20 spinner in `--color-interactive` over "Uploading…" 12/600
  `--color-text-secondary`.
- **Filled:** the photo (cover) with a solid 1px `--color-border` edge. Top-right, 8 in, stacked 4 apart: two
  28 round white buttons with a soft shadow (0 1 3, heading at 16%), 14 icons: `pencil` in `--color-icon`
  (Replace photo) and `trash` in `--color-destructive` (Remove photo). Always visible.

## Upload list

- A card (`cards.md`) with clipping. **Header**, padding 16 16 12 20, gap 12: a 32 tile (`--color-inactive`,
  `cloud-upload`) then the title 16/600 heading ("Uploading 3 files") over a 12 quiet count line ("1 of 3
  checked · 2 did not upload").
- **Batch bar** under the header (padding 0 20 16): 8 high, pill corners, track `--color-surface--background`,
  fill `--color-interactive` for the share of the batch done.
- **Line**, 1px `--color-border` above, padding 12 16 12 20, gap 14:
  - a 44 progress ring (track `--color-surface--background`, arc `--color-interactive`, ring 10% of the size)
    around a 32 round file tile (`--color-surface--background`, 16 icon in `--color-icon`); no arc unless the
    file is going up;
  - name 14/600 heading over a 12 quiet line ("2.0 of 3.1 MB", "Uploaded, now being checked for safety",
    size while waiting);
  - a status pill at the right (`badges.md`): Waiting `--color-inactive`, the percent with a 12 spinner
    `--color-informative`, Checking `--color-warning`, Failed `--color-critical`.
- **Failed line:** the tile turns `--color-critical--surface` with `alert-triangle` in `--color-critical`; the
  reason shows in 12 `--color-critical--onSurface`; then a small secondary "Try again" button with
  `refresh` (only when trying again can help) and a 32 quiet × button.
- **Only failures left:** header tile `--color-critical` with `alert-triangle`, "2 files did not upload" over "Try
  again, or clear them", and a small quiet "Clear" button at the right.

## Files card

Approved 2026-10-19 on board `KuOmH`.

- The Card header (`cards.md`) with a grey `--color-inactive` tile, and a count in the hint line ("4 on this job").
  Side card on record pages; section card (padding 20, photo tiles 4:3) on create pages.
- At the right a small secondary "Add" button with an `upload` icon.

## Files waiting to save

The files card on a create page; nothing uploads until Save. Approved 2026-10-19 on board `KuOmH`.

- Hint line: "4 waiting · they save with the client", "Saving 4 files", "1 did not save".
- **Empty:** a box in `--color-surface--background--subtle`, radius 8, 1.5px dashed
  `--color-border--interactive--hover` edge; centred a 22 `paperclip` in `--color-icon--secondary`, "Add photos and
  documents" 13/600 heading, and "They save with the rest of the page · up to 100 MB each" 12 quiet. Only a
  message; the header's Add picks the files.
- **Photos:** a grid 8 apart in the body (padding 16), tiles 76 high, radius 8, 1px `--color-border`. Each has a
  status pill centred 6 from the bottom ("Not saved" `--color-warning`; "Saving…" `--color-informative` with a
  12 spinner) and a 24 round white remove button top-right (14 `x` `--color-icon`, shadow 0 1 3 heading at 16%),
  always shown.
- **Files:** upload list lines (above) edge to edge under the photos: name over "180 KB · waits for Save" and a
  "Not saved" `--color-warning` pill; while saving, the progress ring and the percent pill.
- **Failed:** inside the body (padding 16) a row with a 1px `--color-critical` edge, radius 8, padding 6, gap 12:
  a 40 `--color-critical--surface` tile with an 18 `alert-triangle` in `--color-critical`; the name 13/600 heading
  over the reason 12 `--color-critical--onSurface`; a small quiet "Retry" (only when trying again can help); a
  28 × button with a 14 `x` in `--color-icon--secondary`.

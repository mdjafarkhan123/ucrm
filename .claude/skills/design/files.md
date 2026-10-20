# Photos and Files

> Dependencies: `colors.md`, `radius.md`, `buttons.md`, `badges.md`, `icon-shapes.md`, `chips.md`, `modals.md`, `page-states.md`

Pencil: `concept.pen` → board "Photos and files" (`b4BxuV`), approved 2026-10-19; Add files, photo labels and photo details on `K04pQm`, approved 2026-10-20; Caption and labels pop-up on `Y0ECPJ`, approved 2026-10-20; record files card on `pH9PB`, approved 2026-10-20.

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
  12/700 white, letter-spacing 0.4, filled in the file family's colour (`colors.md` → File families).
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

## Record files card

The files card on a record page, approved 2026-10-20 on board `pH9PB` (A). Hint line "10 photos · 2 files".

- **Photos**, padding 16, 8 apart: 3 a row, 92 high, radius 8, 1px `--color-border`, cover. With more than six,
  the sixth shows "+4" 20/700 white over `--color-overlay`.
- **Pointing at a photo:** a 2px `--color-interactive` ring and two 28 round white buttons (soft shadow 0 1 3,
  heading at 12%) stacked top-right, 6 in: `tag` Caption and labels (job and visit only) and `x` Remove, 14
  icons in `--color-icon`. Keyboard focus shows them too; touch screens always.
- **Documents** run edge to edge under the photos, a 1px `--color-border` line above each, padding 12 12 12
  16, gap 12: the file picture list line (40), the name 13/600 heading over type · size · date 12 quiet ("· used
  in 2 places" when shared), and a 28 quiet ⋯ (16 `ellipsis`). Open: the ⋯ `--color-surface--active`.
- **Menu:** the line menu look, 208 wide: Download (`download`), a divider, "Remove from this record" (`unlink`)
  in `--color-critical`. View only: Download alone, 184 wide.
- **Notices** at the top of the body, radius 8, padding 10 12, gap 10, 12/500 in the family's `--onSurface`,
  surface fill with its `--surface-edge`: being checked is warning with a 16 spinner ("1 file is being checked
  for safety…"), or `clock-alert` once it takes too long; a failed download is critical with `circle-alert`.
- **Loading:** three 92-high photo bones (radius 8), then two line bones (40 square, two lines); no hint line.
- **Nothing yet, can add:** the dashed empty box with a 22 `images`, "No photos or files yet" and one quiet line.
  **View only:** no Add; centred a 32 grey `images` tile, "No files yet" 13/600 and one 12 quiet line.
- **Couldn't load:** the Notes card's block: 32 critical tile, "Files didn't load", one quiet line, small
  secondary "Try again" (`refresh`).
- **Remove:** the danger "are you sure?" pop-up, `unlink` tile, "Remove <file name>?", Cancel and "Remove".
  Didn't remove: a 14 `circle-alert` and the reason 12/600 `--color-critical` above the buttons.

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

## Add files pop-up

Approved 2026-10-20 on board `K04pQm` (B). A large form pop-up (940): grey `--color-inactive` 40 tile with
`paperclip`, title "Add files" (message composer: "Attach a file"), the record in the hint line.

- **Places**, a 220 side column, `--color-surface--background--subtle`, 1px `--color-border` on its right,
  padding 16 12, lines 2 apart. Captions 12/600 quiet, letter-spacing 0.6 ("ON THIS RECORD", "LIBRARY"), padding 8
  8 6, with 8 extra space before the second. Lines 40 high, radius 8, padding 0 8, gap 10: a 24 tile in the
  place's colour (this record in its record colour, the customer in `--color-client`, library places
  `--color-inactive`: `clock`, `photo`, `file-text`, `files`) and the name 14/500 `--color-text`. Open place:
  `--color-surface`, 1px `--color-border--interactive`, a soft button shadow, name 600 heading.
- **Files side**, padding 20, gap 16: the search box filling the row with a secondary "Upload" (`upload`) beside it,
  then file pictures 4 a row, 12 apart, 128 high, name 13/600 heading over type · size 12 quiet, 8 apart.
- **Pick box** top-left of each picture, 8 in: 22 square, radius 6, `--color-surface` with a 1.5px
  `--color-border--interactive` edge. Picked: the box `--color-interactive` with a white 14 `check`, and a 2px
  `--color-interactive` ring round the picture.
- **Already added:** the picture under a `--color-surface` veil at 72%, centred a white pill (1px `--color-border`,
  padding 4 10, gap 6) with a 14 `check` in `--color-success` and "Already added" 12/600 heading; no pick box.
- **Footer**, padding 12 20, gap 12: at the left the tray — "3 picked" 13/600 heading, then each picked file as
  a 40 picture (radius 8, 1px `--color-border`; a document as a small sheet with its type colour) with an 18 round
  white unpick × (10 `x` `--color-icon`, 1px `--color-border`) on its top-right corner. Then Cancel and the green
  "Add 3 files" (`check`).
- **States** in the files side: no library access is Empty with a grey `lock` tile; nothing here is Empty with a
  grey `files` tile; files uploaded here show as upload list lines with a note row (16 `shield-check` in
  `--color-informative`, 13 `--color-text`) saying they can be picked once checked.

## Photo labels pop-up

Approved 2026-10-20 on board `K04pQm` (A). A small form pop-up (400), grey 40 tile with `tag`, title "Photo
labels", no footer (nothing to save as a whole).

- Body gap 16: the intro line 14 quiet; then the "New label" text box (focus look when open) with a green small
  "Add" (`plus`) beside it, bottoms aligned.
- **List:** rows padding 10 0, 1px `--color-border` between them, gap 6: the label as a look-only grey tag
  (`chips.md`, `--color-inactive` family), then the icon buttons Rename (`pencil`, `--color-icon`) and Remove
  (`trash`, `--color-destructive`).
- **Renaming** turns the row into a text box labelled "Rename Gutter" with small Cancel and green Save under it at
  the right.
- **No labels yet:** a box in `--color-surface--background--subtle`, radius 8, 1.5px dashed
  `--color-border--interactive--hover`; a 22 `tags` in `--color-icon--secondary`, "No labels yet" 13/600 heading
  and a 12 quiet line.
- **Remove** uses the danger "are you sure?" pop-up (`modals.md`) with a `trash` tile and "Remove label".

## Photo details

Approved 2026-10-20 on board `K04pQm` (B). A photo's caption and labels, in the file details panel and the
Describe photo pop-up.

- A card (radius 16, 1px `--color-border`, clipped). **Header**, padding 16 16 12 20, gap 12: a 32 grey tile with
  `photo`, "Caption and labels" 16/600 heading, and at the right a quiet "Manage labels" (14 `settings-2` and 13/600
  in `--color-interactive`, padding 4 6, radius 6) for people who manage files.
- **Body**, padding 0 20 20, gap 14. **Caption box:** `--color-surface--background--subtle`, 1px `--color-border`,
  radius 8, padding 12 14, gap 10: a 16 `quote` in `--color-icon--secondary` and the words 14 heading, line height
  1.45. Clicked or changed, it becomes a field: `--color-surface` with a 1.5px `--color-interactive` edge.
- **Labels:** the tag picker (`chips.md`) with grey tags and "Add labels"; it wraps onto a second line.
- **Save strip**, only once something changed: `--color-surface--background--subtle`, 1px `--color-border` above,
  padding 12 16 12 20, gap 8: an 8 `--color-warning` dot with "Not saved" 13/600 `--color-warning--onSurface`, then
  small Cancel and the green Save (`check`).
- **Look only:** the caption 14 heading, then look-only grey tags; no boxes or buttons.

## Caption and labels pop-up

Approved 2026-10-20 on board `Y0ECPJ` (A). Photo details (above) inside a small form pop-up (400): grey 40 tile
with `photo`, title "Caption and labels", the file name and record in the hint line.

- **Body**, padding 20, gap 14: the photo first, filling the width, 200 high, radius 8, 1px `--color-border`;
  then the caption box and labels without the Photo details card header. A row with the "LABELS" caption (12/600
  quiet, letter-spacing 0.6) and, for people who manage files, the quiet "Manage labels" at the right sits
  above the tags.
- **Footer:** none until something changes; then the Photo details save strip is the footer (padding 16 20).
- **Loading:** the photo, then a 46-high caption bone (radius 8), a 56×12 bone and three 28-high pill bones.
- **Couldn't load:** under the photo, a `--color-surface--background--subtle` block (radius 8, padding 16,
  centred, gap 10): a 32 `--color-critical` tile, "Couldn't load the caption and labels" 14/600 heading, one 12
  quiet line, a secondary "Try again" (`refresh`).
- **Saving:** caption box in the disabled look, Cancel disabled, Save with its spinner; the dot line says "Saving…".
- **Didn't save:** a 14 `circle-alert` and the reason 12/600 `--color-critical` under the labels; the strip stays.
- **Look only:** the caption 14 heading and look-only grey tags. **Nothing yet:** a subtle box (1px
  `--color-border`, radius 8, padding 12 14) with a 16 `quote` and "No caption or labels yet." 14 quiet.

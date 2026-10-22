# Batch 54 — New campaign · Email step (Pencil `Nuydc`, approved B)

Checked live on 2026-10-22 in Chrome (Raad LTD owner, dev server on port 5191, viewport 1874 wide; the step's
column is capped at 1092, so the layout matches 1440). Light and dark.

- `email-step-light.jpg`, `email-step-dark.jpg`: subject with a typed `{{business_name}}` turned into a tag, preview
  text, Text / Button / Service summary blocks, the open block outlined in the email with its "· editing" tag.

## Checked and working

Empty step (email paper stays white in dark, placeholder with icon); add each block type (focus lands in the new
block); variable tag inserted at the caret; Enter starts a new line/paragraph; paste with line breaks; typed
`{{business_name}}` becomes a tag on leaving; inbox line fills in ("News from Raad LTD", "Hi Alex"); half-written
blocks preview as grey stand-ins ("Your heading", "Your photo shows here"); Move up/down keeps focus; Remove moves
focus to the next block; 30-block limit disables Add a block; photo over 25 MB shows the field error; couldn't save
(Button with no link) shows the error card; Save draft (spinner) then reopen redraws tags; first-load bone; couldn't
render (forced 500) then Try again; Mobile width.

## Fixed in this pass

- Preview failed ("could not be rendered") whenever a block was half-written — the preview now accepts unfinished
  content (`marketingPreviewContentSchema`) and the renderer draws empty fields as quiet stand-ins (never in a sent
  email).
- Variable menu inserted at the start of the text, not at the caret.
- After Enter or a paste ending in a line break, the caret went back before the break.
- Focus: new block now takes focus; Move and Remove no longer drop focus to the page.
- Inner double focus ring on tag fields; labelled Variable menu now opens aligned to its button.
- Empty preview in dark mode showed a dark box over the white email; inbox line hidden until the first render.
- Outline over the open block shifted when the frame briefly showed a scrollbar.

Unit checks: `npx vitest run src/lib/marketing/campaign-content.spec.ts src/lib/server/marketing/render-email.spec.ts`.

## Not re-checked live

Real photo upload: R2 refuses browser uploads from the side-by-side port 5191 (CORS preflight 403), so the upload
itself could not run here; the photo box is unchanged by this batch.

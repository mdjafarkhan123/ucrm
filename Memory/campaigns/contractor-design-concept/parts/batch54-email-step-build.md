# Batch 54 — New campaign · Email step build

**Campaign:** contractor-design-concept · **Design:** Pencil `Nuydc` (approved B 2026-10-21); look in design skill
`layout.md` → New campaign · Email step; new behaviour in `c5-shared-parts.md` row 54.
**Stage:** Built, checked live and merged to main 2026-10-22 (`docs/evidence/2026-10-21-batch54/README.md`).
Left: Pencil `Nuydc` step-6 tidy-up (concept.pen was held by the Batch 56 design session), and Jafar's answers below.

## Built

- `marketing/VariableField` (new): tag text field; saved text keeps `{{token}}`; one Backspace/Delete removes a
  tag; caret spaces (zero-width) around tags; paste is plain text; limit counts the saved text.
- `InsertVariableMenu` (icon or labelled button), `CampaignBlockEditor` (closed row / open card, one open at a
  time, PhotoSlot for photos), `CampaignEmailStep` (editor 440 + live email), `CampaignEmailPreview` (new:
  bar, inbox line, email frame measured to its height, outline over the open block), `EmailPreviewBone`
  (shared with `MarketingTemplatePreview`), `block-types.ts`, `ui/DropdownMenu` (`hint`, `iconColor`, `tileSize`,
  `roomy`, `onCloseAutoFocus`), `CampaignJourney` (1092 column on step 3; a failed save shows in the editor).
- Server: preview route takes `mark_blocks` and returns `sender_name`, `subject`, `preview_text`;
  `renderCampaignEmail` option `markBlocks` (preview only; real sends unchanged).
- Unit checks passed: `npx vitest run src/lib/marketing/campaign-content.spec.ts
  src/lib/server/marketing/render-email.spec.ts` (15/15). No type check run (Jafar: once at campaign end).

## Waiting on Jafar (decide, don't fix silently)

- The drawing's email has a business header bar and green buttons; the real email has neither (footer only,
  blue buttons). Left as the real email, so the preview stays honest. Ask: add a header and green buttons to
  every sent email?
- The drawing's grip handles on block rows are left out (no drag to reorder; Move up/down stays).
- At 1440 with the sidebar the column is about 1050, so the email shows about 562 wide, not 600.
- The "N left" count uses the saved length (a variable counts as its `{{…}}` text) because the server's limit does.
- With many blocks the preview stays at the top while the editor scrolls; making it follow (sticky) is his call.
- Empty blocks preview as grey stand-ins ("Your heading", "Your photo shows here"), like Mailchimp and Klaviyo.

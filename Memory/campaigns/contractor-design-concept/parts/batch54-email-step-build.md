# Batch 54 — New campaign · Email step build

**Campaign:** contractor-design-concept · **Design:** Pencil `Nuydc` (approved B 2026-10-21); look in design skill
`layout.md` → New campaign · Email step; new behaviour in `c5-shared-parts.md` row 54.
**Stage:** Built in code, live check half done. **Waiting to merge.**
**Where:** branch `claude/build-batch54`, folder `/home/jafar/Ucrm/.worktrees/build-batch54` (node_modules linked,
`.env` copied), claim `bd9e7bb472e1` (owner `claude-batch54-build`, area `marketing`) — keep it until merged.

## Built (all uncommitted work is now committed on the branch)

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

## Checked live (Playwright, Raad LTD owner, 1440 light)

Empty step; Variable menu; tag in subject; preview inbox line shows "Alex, …"; counts; Backspace/Delete/Home
behaviour around a tag (fixed twice).

## Next

1. Start a dev server in the worktree (`npx vite dev --port 5191 --strictPort`). The Chrome extension was not
   available, so use Playwright: open `/login`, wait for the page to finish loading (`networkidle` + 2.5 s)
   before pressing Sign in (an early press reloads the page), sign in as the Raad LTD owner from `Login.md`.
2. Still to check against `Nuydc`: add each block type; outline + tag over the open block in the email;
   Move up/down; Remove; 30-block limit; photo uploading / over 25 MB; couldn't save (a Button block with no
   link, press Save draft); couldn't render (force a 500) and first-load bone; Mobile switch; paste with line
   breaks (one line vs paragraph); typed `{{business_name}}` becomes a tag on leaving; Save draft then reopen
   (tags redraw); dark mode 1440. Fix differences, screenshot again.
3. Evidence `docs/evidence/2026-10-21-batch54/`; tick `list-1c-parts.md` (`CampaignBlockEditor`,
   `CampaignEmailStep`, `InsertVariableMenu`) and `NOW.md`; Pencil `Nuydc` step-6 tidy-up.
4. Merge: claim `main-integration`, merge into main, push, release both claims, remove the worktree.

## Differences to tell Jafar (decide, don't fix silently)

- The drawing's email has a business header bar and green buttons; the real email has neither (footer only,
  blue buttons). Left as the real email, so the preview stays honest. Ask: add a header and green buttons to
  every sent email?
- The drawing's grip handles on block rows are left out (no drag to reorder; Move up/down stays).
- At 1440 with the sidebar the column is about 1050, so the email shows about 562 wide, not 600.
- The "N left" count uses the saved length (a variable counts as its `{{…}}` text) because the server's limit does.

Stale ticks seen (evidence exists, only the ticks are old): Batches 14, 15, 46, 50 in the lists.

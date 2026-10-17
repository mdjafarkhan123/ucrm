# Settings redesign — workflows group progress (2026-10-17)

Branch `codex/settings-workflows-app`, port 5215, claim `settings-workflows-app`. **Implemented, pending final validation.**
Visual only: behaviour, data, permissions, validation and saves unchanged.

**Deferred at Jafar's request:** type checks, svelte-check, lint, automated tests, production builds and full-project scans.
Phone width and keyboard checks are also not done (desktop-only agreement).

## Routes

| Route | Pencil frame | Status | Evidence (Playwright, 1440px, signed in as the Raad LTD owner; Chrome extension was not connected) |
| --- | --- | --- | --- |
| price-book | j1chB1 | done | `scratchpad shots/pb-light.png`, `pb-dark.png`; no console errors from the page |
| pipeline | Q25PS | done | `scratchpad shots/pipe-light.png`, `pipedirty-dark.png` (unsaved bar triggered locally, nothing saved) |
| checklists | YZ8Wg (original card grid) | done | `scratchpad shots/checklists-light.png`, `checklists-dark.png`; only 1 template in test data |
| automation (index) | n0kJri | done | `scratchpad shots/auto2-light.png`, `auto2-dark.png` |
| forms (index) | Wr392 | done | `scratchpad shots/forms2-light.png`, `forms2-dark.png` |

Not started — no approved Pencil frame for these sub-pages (need Jafar's design approval first):
price-book/import, automation/new, automation/[id], automation/[id]/edit, forms/[id].

## Shared piece added

`src/routes/(app)/settings/_workflows/WorkflowPageHeader.svelte` — icon tile + breadcrumb + title + actions, with a `tone`
prop (blue default, yellow for Automation). The business session built a similar `BusinessSettingsPresentation`;
**Codex reviewer: consolidate the two into one shared Settings header.**

## Known gaps

- Test data is thin: Checklists archived card, Forms Default/Draft/Archived badges and the Automation allowance meter
  (account has unlimited automations) were not seen live.
- Price book: one test item's photo returns 409 from `/api/files/.../view` (test data, not this change).
- Pipeline: three card sections are now `section`/`h3` instead of `fieldset`/`legend`; saving lock still works through the wrapping fieldset.
  Save bar is a dark centred bar that always shows (as before it was always visible); Pencil draws it only when unsaved.
- Row menus use the shared DropdownMenu; Pipeline stage/reason menus still show vertical dots (Pencil: horizontal).
- Automation: Paused pill drawn grey (Draft is amber); Pencil draws Paused yellow. Needs Jafar's pick.
  `RecordListCard` has no icon slot, so the yellow tile beside "Your automations" is omitted.

## Next action

Codex reviews and merges. Then run the deferred checks. Sub-pages above wait for Pencil approval.

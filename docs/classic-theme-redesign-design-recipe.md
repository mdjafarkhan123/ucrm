# Classic theme redesign — design recipe

How to design and build screens for the [Classic theme redesign](classic-theme-redesign-behavior-contract.md)
so every page matches the **reference screens** — the new Classic look Jafar chose on 2026-10-13 ("This will
be our classic design, we will build design system based on your version. No more old version."):

- `Settings · Home · 1440` (frame `XwqtP`) — index page: business banner, grouped setting tiles, rail of
  account, balance and setup status.
- `Settings · Business profile · 1440` (frame `ofzTY`) — form page: form cards, customer preview rail,
  floating Save bar.

**The design-system page** — `Classic design system · light` (frame `GIgyC`) with its dark copy
`Classic design system · dark` (`yRKPF`) — sits first in `classic.pen`, the two reference screens beside it.
It holds every token and every shared part. Both reference screens are built from its parts (instances), so a
change to a part there reaches every screen. When the reference screens and this recipe disagree, the
screens win and this recipe is corrected.

**Design review update (2026-10-13):** Jafar's answers changed the concept — the app's brand green
(`green`, the app's `--color-interactive` `#037741`) and its deeper shades replace every lime and other
green — no light green in light mode (Jafar: "dont use light green in white mode"; light greens belong to
dark mode); a near-black green replaces navy ink on dark surfaces; the main button is brand green with white
text; dark mode later moved to calm slate (see § Tokens, 2026-10-14); Settings gains a Sales & work group; no text is lighter than `muted`.

**Superseded look:** the earlier family — the first-concept job, quote and invoice screens, deleted
2026-10-13 once the six record pages were approved — and the old Classic design-system page (`lkPLl`, dark `lVZIm`) with its 23 record-page tokens. Their **page structure** stays
approved (§ Record page structure); their look is replaced by this recipe.

**Token names:** this recipe writes Pencil tokens without their `classic2-` prefix — `muted` is
`classic2-muted`. Screens use token names, never raw values. A few decorative glows inside the featured card
and the Save bar's amber dot keep raw tinted values; they look the same in both modes. When the first version
is built, the tokens become the app's Classic CSS variables and this recipe moves into the `design-classic`
skill.

## Working method

1. **Know the page's real content.** Read the page's `+page.svelte` and list every section, rail card and
   conditional block it renders. Done when each section maps to a place in the design, or to a menu, tab or
   hover reveal. Every feature drawn exists in that code or in the plan's § Approved additions; anything new
   is shown to Jafar as a proposal and listed in the plan's § Still unclear until he says yes.
2. **Start from the design-system page.** Place instances of its parts — Sidebar, Top bar, page headers, cards,
   rows, fields, rail cards — and change their content through overrides. Use token names for every colour.
   When a part has to look different, change it on the design-system page first. Draw a new part only when
   none fits: build it there as a component with token colours, then place it.
3. **Fill it with a realistic, busy record.** One believable contractor scenario (Raad LTD, Burnaby BC) with
   real names, dates, amounts that add up, and work in progress. Empty states come after the busy state is
   approved.
4. **Build section by section,** checking Pencil's layout problems after each. Pencil reports "clipped" for
   content below a frame's current height and warns about `fill_container` dividers; measure with `Get`
   bounds and give dividers a fixed height. Pencil `execute` globals do not survive between calls; carry
   node ids forward as literals.
5. **Critique like a picky designer.** Export the frame with `Export(..., "png", ..., {scale:1})`, crop it into
   halves with `magick`, and read each half at full size. Hunt for clipped or badly wrapped text,
   misalignment, overlapping parts, one row styled differently from its siblings, the same fact twice,
   invented features, wording that differs from the app, and colour that breaks § Colour rule. Check dark mode
   by setting the frame's `theme` to `{mode:"dark"}`, export, set it back.
6. **Fix and repeat** until a fresh round finds nothing — at most three rounds — then fit the frame height.
7. **Hand over.** Tell Jafar the screen names, what each shows and which parts are new; ask him to press
   Ctrl+S in Pencil, then commit `classic.pen` from the main folder.

## Colour rule

Jafar, 2026-10-13: colour "where it make sense", never a decorative rainbow — "follow the best UI/UX
designer". The base is calm: white cards, cool grey page, ink text, a black-green sidebar and dark surfaces, and one brand green for the main
button and highlights. Colour
appears only when it means one of three things:

| Meaning | Colours | Where |
| --- | --- | --- |
| **Section** — which group a setting belongs to | Business green, Sales & work teal, Communications blue, Automations amber, Team & access violet | Tab dot, solid group icon, soft tile icons |
| **Record type** — what kind of record | Quote rose, invoice blue, request amber, job green, client/people violet | Record chips, "where used" tiles, record pills and tracks |
| **Status** — what state it is in | Red to do, amber waiting / in review, green ready / done | Status pills, count chips, attention rows |

Sidebar icons, cards, secondary buttons and form controls stay neutral; the one main button per page is
brand green. One dark featured card per page at most.

**Coloured icon tiles** (approved by Jafar 2026-10-13 on the six record pages). Jafar's rule: colour must be meaningful and
representative — a coloured icon always tells the user something; otherwise it stays neutral. A coloured tile
follows the Settings row tile: `<colour>-tint` fill, `<colour>-soft` stroke, icon in the deep `<colour>`.

- **Status:** a key fact's tile turns its status colour only when its value needs attention — green for
  happening today (a job's Schedule while the crew is on site, a request's assessment today), amber for waiting
  on someone (a quote's "Approved: No answer yet"), red once overdue (an invoice's Due). Close-out and deposit
  items still waiting are amber. Every other key fact keeps the neutral tile.
- **Record type:** a rail row about another record takes that record's colour (Billing's invoice row blue).
- **Automation:** reminder and automation rows are amber.
- **Neutral:** everything else — instructions, discount, tax, lead source, marketing email, contact facts,
  header meta icons, button icons and table rows — uses the `chip` or `surface-soft` tile with a neutral icon.
  Side-rail row tiles are 32, radius 9, 16 icon.

## Tokens

Light and dark values of every colour token (`classic2-…` in `classic.pen`). Dark mode uses calm slate
surfaces from Jobber's dark theme (Jafar, 2026-10-14: option D — the near-black green read as "neon"): green
appears only as the solid brand-green main button and as softer `green` text and marks. The sidebar, featured
card and Save bar stay dark in both modes; in dark mode the sidebar turns neutral near-black.

| Token | Role | Light | Dark |
| --- | --- | --- | --- |
| `page` | Page background | `#F3F4F7` | `#171B1C` |
| `surface` | Cards, inputs | `#FFFFFF` | `#232B2F` |
| `surface-soft` | Toggle panel, locked input, secondary button, preview fade | `#F6F7F9` | `#2A3438` |
| `chip` | Chips, Ctrl K, role badge, neutral icon tile, unit suffix | `#F3F4F7` | `#2E393D` |
| `border` | Card border; count chip fill | `#E9EBF0` | `#34454B` |
| `divider` | Row and column dividers | `#EEF0F3` | `#2E3A3F` |
| `border-control` | Buttons, search, pills | `#E6E8EE` | `#4C5F67` |
| `border-input` | Inputs; switch off | `#DDE1E8` | `#4C5F67` |
| `ink` | Titles, headings, values | `#101828` | `#F1F4F5` |
| `body` | Labels, strong body, secondary button text | `#344054` | `#CDD5D8` |
| `secondary` | Subtitles, count chip text | `#5B6475` | `#A7B4BA` |
| `muted` | Small text, help, placeholders — no text lighter | `#667085` | `#8D9AA0` |
| `icon-muted` | Chevrons and field icons only, never text | `#98A2B3` | `#6E7D84` |
| `required` | Required asterisk | `#E11D48` | `#FB7185` |
| `green` | Links, green text, ticks, progress, focus ring | `#037741` | `#4CB782` |
| `green-hover` | Main button hover | `#02532D` | `#038548` |
| `green-on` | Text and icons on a main button | `#FFFFFF` | same |
| `green-mid` | Switch on | `#049A54` | `#4CB782` |
| `green-deep` | Green pill text (role pill) | `#02532D` | `#8FD9B0` |
| `green-tint` / `green-soft` | Business tile fill / stroke; green status pill fill | `#F2FBF6` / `#D7F5E5` | `#1F3A2E` / `#2A4D3D` |
| `teal`, `-tint`, `-soft`, `-dot` | Sales & work | `#0E6171`, `#F3FBFC`, `#DEF3F7`, `#15A4C1` | `#68C8D7`, `#11303A`, `#1B4450`, `#15A4C1` |
| `blue`, `-tint`, `-soft`, `-dot` | Communications; invoice | `#1D4ED8`, `#EFF6FF`, `#DBEAFE`, `#3B82F6` | `#82A9FF`, `#15253F`, `#223A63`, `#3B82F6` |
| `amber`, `-tint`, `-soft`, `-dot` | Automations; request; waiting | `#B45309`, `#FFFBEB`, `#FEF3C7`, `#F59E0B` | `#F4B15D`, `#33260F`, `#4A3815`, `#F59E0B` |
| `violet`, `-tint`, `-soft`, `-dot` | Team & access; client / people | `#6D28D9`, `#F5F3FF`, `#EDE9FE`, `#8B5CF6` | `#BA9CF5`, `#261E3D`, `#352A57`, `#8B5CF6` |
| `rose`, `-tint`, `-soft` | Quote; to do | `#BE123C`, `#FFF1F2`, `#FFE4E6` | `#F58CA8`, `#3A1A24`, `#4F2130` |
| `solid-green` / `-teal` / `-blue` / `-amber` / `-violet` | Main button and solid green fills (`solid-green`); solid group icon tiles, page icon tile (white icon) | `#037741` / `#118197` / `#1D4ED8` / `#B45309` / `#6D28D9` | same, blue `#2F5FE0`, amber `#C2610C`, violet `#7C3AED` |
| `alert-dot` | Notification dot | `#F43F5E` | same |
| `sidebar` / `sidebar-top` | Sidebar gradient bottom / top | `#08150F` / `#10291F` | `#111516` / `#1C2326` |
| `sidebar-active` | Active nav item, sidebar count badge | `#037741` | same |
| `sidebar-text` / `-muted` / `-group` | Nav label / nav icon, sub text / group label | `#D3DED8` / `#93A89C` / `#86A093` | `#D5DCDE` / `#8D9AA0` / `#85939A` |
| `sidebar-overlay` / `sidebar-line` / `sidebar-edge` | Brand block fill / hairlines / outline | `#FFFFFF0D` / `#FFFFFF14` / none | same / same / `#FFFFFF14` |
| `selected` | Lit jump pill | `#08150F` | `#037741` |
| `savebar` | Save bar | `#08150F` | `#2A3438` |
| `feature-mid` / `feature-end` / `feature-glow` | Featured gradient and glow (starts at `sidebar`) | `#01361D` / `#02532D` / `#049A5459` | same |
| `feature-chip` / `feature-line` / `feature-ring` | Fact chip fill / stroke / hairline rings, Cancel fill | `#FFFFFF0F` / `#FFFFFF1A` / `#FFFFFF14` | same |
| `feature-eyebrow` / `-meta` / `-label` / `-muted` / `-icon` / `-button-text` | Text on dark surfaces | `#C2D6C9` / `#D5E3DA` / `#D5E3DA` / `#B4C9BC` / `#FFFFFFB3` / `#E5E9F0` | same |
| `logo-start` | Logo and avatar gradient start (ends `solid-green`) | `#049A54` | same |
| `white` / `on-white` | Text on dark surfaces / text on a white button there | `#FFFFFF` / `#0B1220` | same |
| `shadow-near` / `-far` / `-lift` | Card and input shadow / card far / preview document | `#1018280A` / `#1018280D` / `#1018281A` | `#0000004D` / `#00000040` / `#00000059` |
| `shadow-green` / `-feature` / `-savebar` | Main button / featured card / Save bar | `#03774333` / `#08150F2E` / `#08150F4D` | `#00000040` / `#00000066` / `#00000080` |

Shadows: card y1 b2 `shadow-near` + y10 b28 `shadow-far`; input y1 b2 `shadow-near`; main button y6 b16
`shadow-green`; featured card y18 b40 `shadow-feature`; Save bar y18 b40 `shadow-savebar`; solid icon tile y4
b10 in its colour at 25%. Font: Inter (Jafar, 2026-10-13). Icons: Lucide in Pencil, the matching Tabler icon
in code.

**Parts on the design-system page** (components; use instances): Sidebar, Sidebar · collapsed, Top bar,
Page header · index, Page header · sub page, Button · main / secondary / icon / small / on dark, Jump pill and
Jump pill · in view, Status pill · ready / waiting / to do, Count chip, Attention count, Role badge, Group
header, Setting row (optional role badge and status pill, hidden until switched on), Form card header,
Field · text / with icon / select / locked / with unit / textarea / error, Toggle row, Featured card,
Save bar · unsaved / resting, Rail card · account / figure / status list / preview / where used, Segmented
control (two or three options; the lit one on `surface` with the card shadow, others `secondary` text).

## Page and shell

- **Frame:** 1440 wide, page fill, padding 12, sidebar and content 20 apart.
- **Sidebar:** 248 wide, full height, radius 24, vertical black-green gradient `sidebar-top` → `sidebar`, padding
  18/14/16/14, gap 18. Brand block: radius 16, fill `sidebar-overlay`, stroke `sidebar-line`, padding 10; 40 logo tile
  showing the business's own logo from Branding (radius 12; with no logo, gradient `logo-start` → `solid-green`,
  `white` leaf), name 15/700 `white`, "Workspace · Owner" 12/500 `sidebar-muted`, and the app's collapse button
  (`panel-left-close` 18, `sidebar-muted`) — there is no workspace switching. The collapsed sidebar shows icons
  only. Group label 11/700 uppercase, letter-spacing 0.8, `sidebar-group`. Item 38 high, radius 12, padding 0/12,
  gap 12, icon 18 `sidebar-muted`, label 14/500 `sidebar-text`. Active item fill `sidebar-active`, icon and label
  14/600 `white`. Count badge: 20 high `sidebar-active` pill, 11/700 `white`. The sidebar carries a 1px
  `sidebar-edge` outline (visible in dark mode only). Settings pinned at
  the bottom under a `sidebar-line` hairline.
- **Content column:** padding 8/12/24/4, gap 24.
- **Top bar** (no card): search 440×44, radius 14, `surface`, `border-control` border, 18 icon, 14/500 placeholder
  `muted` "Search anything in your workspace" (it finds settings too), "Ctrl K" chip (radius 8,
  `chip`). Right: 44 square icon buttons (radius 14, `surface`, bordered; the
  bell carries a 9px rose dot), the brand green "Add new" main button, a 44 avatar circle (gradient
  `solid-green` → `feature-end`, `white` initials 14/700).
- **Page header:** index pages — eyebrow 11/700, letter-spacing 1, `secondary` after a 6px `green` dot; title
  36/800, letter-spacing −1.2, ink; subtitle 15/500 `secondary`. Sub pages — 60 brand green
  `solid-green` icon tile (radius 18, `white` 28 icon); breadcrumb 13/600 `green` link, chevron, 13/500 secondary; title 30/800,
  −0.9; subtitle 14/500; a `surface` bordered "Last changed by … · date" chip right.
- **Body:** main column fills, rail 336 wide, 20 apart. Main stacks 24 apart on index pages, 20 on form pages;
  rail cards 16 apart.

## Cards and rows

- **Card:** `surface`, radius 20, 1px inner border `border`, card shadow, clipped.
- **Group header** (index pages, outside its card, 12 above it): 36 solid icon tile in the section colour
  (radius 11, `white` 18 icon), title 18/700, −0.3, ink + count chip (11/700 `secondary` on `border`, pill),
  subtitle 13/500 `muted`.
- **Setting rows:** two columns in one card, 1px `divider` dividers between rows and columns, an empty cell
  when the count is odd; a group with one setting spans the full width. Row padding 16/18, gap 14: 40 icon tile (radius 12, section tint fill and stroke, 19
  icon in the section's deep colour), title 14/600 `ink`, description 12/500 `muted` at 1.45, chevron
  16 `icon-muted`. A role badge sits beside the title (neutral `chip`, lock 10, 11/600 `secondary`); a status pill
  ("Incomplete", "Not set") sits before the chevron when the app shows one.
- **Form card:** header padding 20/24/18/24 — 36 tint icon tile (radius 11) in the page's section colour,
  title 16/700, −0.2, subtitle 13/500 `muted`; body padding 0/24/24, gap 16; fields in a row 14 apart. Two
  short cards may share a row and share its height.
- **Jump pills:** 38 high pills, 8 apart, padding 0/16/0/14, one per group the viewer can see; each jumps to
  its group and the group in view is lit. No "All settings" pill and no counts — counts live on group
  headers. Lit: `selected` fill (black-green; brand green in dark mode), 8px section dot, 13/600 `white` label. Others: `surface`, `border-control`
  border, 8px section dot, 13/600 `body` label.

## Fields and buttons

- **Field:** label above, 13/600 `body`, required `*` 13/700 `required`, "Optional" 12/500 `muted`.
  Input 44 high, radius 12, `surface`, `border-input` border, input shadow; value 14/500 `ink`, placeholder
  `muted`; optional 16 leading icon `icon-muted`; select chevron-down 16; unit suffix chip (12/600 on `chip`,
  radius 8). Help line 12/500 `muted`.
- **Locked field:** fill `surface-soft`, no shadow, value `muted`, a lock icon instead of the chevron, help line
  led by a 13 lock icon `icon-muted` with the app's reason.
- **Textarea:** 88 high, padding 12/14, line height 1.5; "N characters left" right, 12/500 `muted`.
- **Toggle row:** `surface-soft` panel, radius 14, padding 14/16; title 14/600, help 12/500; switch 44×26, on
  `green-mid` with a `white` 20 knob; off `border-input`.
- **Buttons:** main button brand green `solid-green` (hover `green-hover`), radius 14 (12 inside cards), 44 high in headers and 40 in
  cards, 14/600 `green-on` label and icon, `shadow-green`; disabled at 45% opacity with no shadow; keyboard
  focus adds a 3px `green-soft` ring — one per
  page, named for the next step; the top bar's "Add new" is the shell's own. Other card actions are
  secondary: `surface-soft`, `border-control` border, 13/600 `body` label and icon. On dark surfaces: `white` button
  with `on-white` label. Small row action: 30 high, radius 9, `solid-green`, 12/600 `green-on`.

## Featured card

One per page. The Settings banner: radius 24, padding 28, gap 22, linear gradient 120° `sidebar` →
`feature-mid` (60%) → `feature-end`, featured shadow; a 420 radial green glow `feature-glow` → transparent at the top
right with two hairline rings (`feature-ring`, `sidebar-overlay`). 64 logo tile (radius 18, gradient `logo-start` →
`solid-green`, white 30 leaf, green glow); eyebrow 11/700, letter-spacing 1, `feature-eyebrow`; name 28/800, −0.8, white;
meta 14/500 `feature-meta`; `white` button right. Fact chips: four equal, radius 14, fill `feature-chip`, stroke
`feature-line`, padding 12/14; label row 14 `feature-icon` + 11/600 `feature-label`; value 13/600 `white`. On record pages
the profit card (job, quote) and the balance-due card (invoice) take this featured style — to design in Part 2.

## Rail cards

- **Account:** 56 avatar (`logo-start` → `solid-green` gradient, 3px `surface` ring), "SIGNED IN AS" 11/700 `muted`, name 17/700, green
  role pill (`green-soft`, crown 11, 11/700 `green-deep`); two full-width secondary buttons stacked 8 apart.
- **Figure card** (Communication Balance): 28 tint icon box in the section colour, eyebrow 11/700, letter-
  spacing 0.8, `muted`; figure 34/800, −1, ink; two lines 12/500 (`secondary`, then `muted`); full-width
  secondary button.
- **Status list** (Setup status): header 16/700 + a red chip counting only the items the owner must act on ("1 to do"); rows padding 12/20 with a top divider —
  34 neutral icon tile (`chip`, `body` icon), title 13/600, text 12/500 `muted`; right side a green
  30-high action or a status pill (tint fill, 6 dot, 11/700 status colour).
- **Preview** (What customers see): card fill fades `surface-soft` → `surface`; green "Live preview" pill; inside, a
  `surface` document (radius 14, `border-control` border, shadow y12 b24 `shadow-lift`, padding 18) showing the logo,
  name, record chip in its record colour, tagline, contact rows with 13 `muted` icons, and three
  `divider` skeleton lines.
- **Where this is used:** rows padding 11/20 with top dividers; 32 tile (radius 10) in the record colour of
  what it affects; title 13/600, text 12/500.

## Save bar

Floating `savebar` bar (black-green; slate `#2A3438` in dark mode) centred over the content column: 720 wide, 64 high, radius 20, padding 0/10/0/20, Save bar
shadow. Left: 28 circle `#F59E0B26` with an 8 `#FBBF24` dot; "You have unsaved changes" 14/600 `white` over
"Nothing is saved until you press Save." 12/500 `feature-muted`. Right: Cancel (44 high, radius 14, `feature-ring`,
`feature-line` stroke, 14/600 `feature-button-text`) and Save (main button: `green`, `green-on` check 16 and 14/700 label, primary
shadow). It appears exactly when the shared save rules say the bar shows; Jafar approved the two text lines
2026-10-13. Full-page forms show the bar all the time: while nothing has changed it takes a resting state
— dot `feature-chip` with a `feature-muted` dot, "No unsaved changes" over "Change any field, then press
Save.", Cancel and Save at 45% opacity (part `Save bar · resting`).

## Record page structure

From the earlier family, approved by Jafar 2026-10-13 ("Looks good, continue"). Layout, order and sizes
stand; old token names (`$color-…`) map to § Tokens and § Colour rule when the job, quote and invoice
screens are restyled — the primary button becomes `green` with `green-on` text, the record's own pill and track take its record
colour, "now" is brand green.

- **Header card:** padding 24/28/0/28. Row 1: status pill (record colour, pill, 7px dot, 12/600) + record
  number 12/600, letter-spacing 0.6, secondary + 3px dot + record kind 12/500; right: 40×40 history button,
  40-high "More ⌄", then the primary button named for the next step. Title 32/700, −0.8, 18 below row 1.
  Meta row: 28 client avatar + name 14/600; icon-15 + 14/500 secondary facts 16 apart (the address, not the
  phone number — Call carries it); quick contact buttons right (34 circles, bordered).
- **Lifecycle track** (lighter version, Jafar 2026-10-14): the same five steps on every work record — Request,
  Quote, Job, Invoice, Paid — each page lighting its own; a done step's sub-line says when ("Approved Sep 28"),
  the current one what it waits on ("Waiting on David", "Due in 7 days"). Five equal steps, 14 apart, 22 above
  and 20 below; 4px pill bars, 10 to the labels. No icon tiles. Label 13/600: a done step starts with a
  check-13 in `green` and keeps its number and open arrow ("✓ Request #88 ↗"); the current step starts with a
  7px dot in its sub-line's colour and shows only its name ("● Job"), because the record number already sits
  in row 1; a future step's label is `muted`. Sub-line 12/500, 3 below the label.
- **Key facts strip:** top divider, padding 18/0/22; four equal facts with 1px dividers and 16 side padding
  (the first none); each a 36 icon tile (kept, Jafar 2026-10-14), 10 gap, label 12/500 secondary, value
  14/600. Facts that live nowhere else on the page, plus the record total. Editable facts (an invoice's terms
  and dates) end the strip with a 32 bordered pencil button instead of a separate section.
- **Phone (390):** card padding 18/18/0/18. Row 1 status pill + record number only. Title 24/700, −0.5,
  wraps. Client name, then the address on its own line. The main action takes the full width (44 high) with a
  44 "⋯" More button beside it; History moves into More. Call / Message / Directions become three equal 38-high
  labelled buttons. Track: bars with step names 11/600 under them, then one line "● Job · Visit 3 of 4 · now"
  13/600 in the current step's colour. Key facts in a 2 × 2 grid with their icon tiles; the invoice's pencil
  becomes a full-width "Edit terms and dates" button under the grid.
- **Lists of dated work:** date tile 52×56, radius 12, bordered — weekday 10/700, letter-spacing 0.6, day
  20/700; today's tile filled `green` with a `green-on` day. Title 15/600, time 13/500 secondary, note 12/500
  with a 13 icon. Today's row tinted with a green live note ("Clocked in 8:04 AM · on site 2h 16m"). Crew
  avatars 30, overlapping by 5, 2px ring in the row's background. Status pills in a 124-wide column: done,
  now (filled), scheduled. Row action: borderless 36 button, chevron (pencil for editable future rows).
- **Tabs inside a card:** labels 14/600 (inactive secondary) each with a value chip; active tab has a 2px
  green underline. Used for the job's Work log and the invoice's History (Payments, Edits).
- **Products and services:** the app's wording — card title "Products and services", columns Line item,
  Quantity, Unit price, Total. Table head 10/24 padding on the subtle fill, labels 11/600 uppercase,
  letter-spacing 0.6. Numbers right-aligned; a 300-wide totals block holds every money row — subtotal,
  discount, tax, record total (14/700 label, 18/700 value above a divider). Add-ons carry a neutral
  "Recommended add-on" pill. A locked block explains why in a footer strip (lock icon + the app's message).
- **Right rail order:** money first, then wrap-up, then reference — profit, close-out, billing, instructions,
  photos and files, notes. Photos and files always sit in the rail. Job and quote show profit (team only;
  the quote's split is Cost and Estimated profit); the invoice shows Balance due (Paid and Balance, plus the
  client account balance).
- **Close-out:** a 52 ring (inner radius 0.78, count in the middle) beside the title; items with a 24 state
  circle (done filled `green-mid` with a `white` check, waiting with an hourglass, to-do a 1.5 outline), label
  14/600, state 12/500, and a 30-high bordered action when the user can act.
- **Photos:** three-column grid of 92-high radius-12 tiles, 8 apart; the last carries a dark overlay with
  "+N" 18/700 white. Files follow as rows with a 34 file-type tile.
- **Notes:** 28 avatar, author 13/600 and time 12/500 on one line, text 13/500 at 1.5; a 40-high composer on
  the subtle fill with a 28 green send button.
- **Text sections** (introduction, client message, disclaimer): compact cards of 14/500 text at 1.55;
  related ones share one card as labelled rows.
- **Avatars:** initials avatars keep one colour pair per person across the page.
- **Layout moves Jafar accepted 2026-10-13:** invoice Terms & dates folded into the key facts strip; discount
  and tax as rows in the totals block; quote photos in the rail; History card tabs on the invoice.

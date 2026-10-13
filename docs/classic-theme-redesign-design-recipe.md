# Classic theme redesign — design recipe

How to design and build screens for the [Classic theme redesign](classic-theme-redesign-behavior-contract.md)
so every page matches the **reference screens** — the new Classic look Jafar chose on 2026-10-13 ("This will
be our classic design, we will build design system based on your version. No more old version."):

- `Settings · Home · Claude concept · 1440` (frame `XwqtP`) — index page: business banner, grouped setting
  tiles, rail of account, balance and setup status.
- `Settings · Business profile · Claude concept · 1440` (frame `ofzTY`) — form page: form cards, customer
  preview rail, floating Save bar.

Both sit in `classic.pen` below the older screens. When the reference screens and this recipe disagree, the
screens win and this recipe is corrected.

**Design review update (2026-10-13):** Jafar's answers changed the concept — the app's brand green `#037741` (its
`--color-interactive`) and its deeper shades replace every lime and other green — no light green in light
mode (Jafar: "dont use light green in white mode"; `#05BE68` and lighter belong to dark mode); a near-black green replaces navy ink on dark surfaces; the main
button is brand green with white text; Settings gains a Sales & work group; no text is lighter than `#667085`.
The values below include these changes.

**Superseded look:** the earlier family — `Job details · Claude concept · Job cockpit · 1440` (`oNoOG`), quote
(`Ae1NJ`), invoice (`fPq9c`), the first Settings screens (`aRN8m`, `f07YA`) — and the old Classic
design-system page (`lkPLl`, dark `lVZIm`) with its 23 record-page tokens. Their **page structure** stays
approved (§ Record page structure); their look is replaced by this recipe.

**Status:** values below are raw hex as drawn, light mode only. Part 2 rebuilds the Classic design-system page
from them as named tokens with light and dark values; from then on screens use token names, never raw values.
When the first version is built, this recipe moves into the `design-classic` skill.

## Working method

1. **Know the page's real content.** Read the page's `+page.svelte` and list every section, rail card and
   conditional block it renders. Done when each section maps to a place in the design, or to a menu, tab or
   hover reveal. Every feature drawn exists in that code or in the plan's § Approved additions; anything new
   is shown to Jafar as a proposal and listed in the plan's § Still unclear until he says yes.
2. **Start from the reference screens.** Copy the shell — sidebar `r8ENCY`, top bar `nHqiG` (frame `XwqtP`) —
   and the nearest parts, then change content. Draw a new part only when none fits, and give it the rules
   below.
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
   invented features, wording that differs from the app, and colour that breaks § Colour rule. Once tokens
   have dark values, check dark mode by setting the frame's `theme` to `{mode:"dark"}`, export, set it back.
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

## Palette (light)

| Role | Value |
| --- | --- |
| Page | `#F3F4F7` |
| Surface (cards, inputs) | `#FFFFFF` |
| Subtle fill (chips, toggle panel, locked input, secondary button) | `#F6F7F9`, chips `#F3F4F7` |
| Card border (inner) / row divider | `#E9EBF0` / `#EEF0F3` |
| Control border / input border | `#E6E8EE` / `#DDE1E8` |
| Ink — page titles, text on green buttons | `#0B1220` |
| Black green — sidebar, Save bar, selected pill, page icon tile, featured base | `#08150F`; sidebar top `#10291F` |
| Heading / body strong / label | `#101828` / `#344054` |
| Secondary / muted, placeholder and small text | `#5B6475` / `#667085` — no text lighter; `#98A2B3` icons only |
| Brand green (`--color-interactive`) — main button, Save, logo tile, badges, active nav, brand dots | `#037741`, hover `#02532D` |
| Deep green — green text and links, Business icons; switch and solid fills | `#037741`; `#049A54`; very deep `#02532D`, `#01361D` |
| Required asterisk / notification dot | `#E11D48` / `#F43F5E` |

Tints (fill · stroke · icon/text · dot): green `#F2FBF6 · #D7F5E5 · #037741 · #049A54`; teal
`#F3FBFC · #DEF3F7 · #0E6171 · #15A4C1` (solid `#118197`); blue
`#EFF6FF · #DBEAFE · #1D4ED8 · #3B82F6`; amber `#FFFBEB · #FEF3C7 · #B45309 · #F59E0B`; violet
`#F5F3FF · #EDE9FE · #6D28D9 · #8B5CF6`; rose `#FFF1F2 · — · #BE123C`. Status pills: red `#FFE4E6` /
`#BE123C`, amber `#FEF3C7` / `#B45309`, green `#D7F5E5` / `#037741`.

Shadows: card y1 b2 `#1018280A` + y10 b28 `#1018280D`; input y1 b2 `#1018280A`; primary button y6 b16
`#03774333`; featured card y18 b40 `#08150F2E`; Save bar y18 b40 `#08150F4D`; solid icon tile y4 b10 in its
colour at 25%. Font: Inter (Jafar, 2026-10-13). Icons: Lucide in Pencil, the matching Tabler icon in code.

## Page and shell

- **Frame:** 1440 wide, page fill, padding 12, sidebar and content 20 apart.
- **Sidebar:** 248 wide, full height, radius 24, vertical black-green gradient `#10291F` → `#08150F`, padding
  18/14/16/14, gap 18. Brand block: radius 16, fill `#FFFFFF0D`, stroke `#FFFFFF14`, padding 10; 40 logo tile
  showing the business's own logo from Branding (radius 12; with no logo, gradient `#049A54` → `#037741`,
  white leaf), name 15/700 white, "Workspace · Owner" 12/500 `#93A89C`, and the app's collapse button
  (`panel-left-close` 18, `#93A89C`) — there is no workspace switching. The collapsed sidebar shows icons
  only. Group label 11/700 uppercase, letter-spacing 0.8, `#86A093`. Item 38 high, radius 12, padding 0/12,
  gap 12, icon 18 `#93A89C`, label 14/500 `#D3DED8`. Active item fill `#037741`, icon and label
  14/600 white. Count badge: 20 high `#037741` pill, 11/700 white. Settings pinned at
  the bottom under a `#FFFFFF14` hairline.
- **Content column:** padding 8/12/24/4, gap 24.
- **Top bar** (no card): search 440×44, radius 14, white, `#E6E8EE` border, 18 icon, 14/500 placeholder
  `#667085` "Search anything in your workspace" (it finds settings too), "Ctrl K" chip (radius 8,
  `#F3F4F7`). Right: 44 square icon buttons (radius 14, white, bordered; the
  bell carries a 9px rose dot), the brand green "Add new" main button, a 44 avatar circle (gradient
  `#037741` → `#02532D`, white initials 14/700).
- **Page header:** index pages — eyebrow 11/700, letter-spacing 1, `#5B6475` after a 6px `#037741` dot; title
  36/800, letter-spacing −1.2, ink; subtitle 15/500 `#5B6475`. Sub pages — 60 brand green
  `#037741` icon tile (radius 18, white 28 icon); breadcrumb 13/600 `#037741` link, chevron, 13/500 secondary; title 30/800,
  −0.9; subtitle 14/500; a white bordered "Last changed by … · date" chip right.
- **Body:** main column fills, rail 336 wide, 20 apart. Main stacks 24 apart on index pages, 20 on form pages;
  rail cards 16 apart.

## Cards and rows

- **Card:** white, radius 20, 1px inner border `#E9EBF0`, card shadow, clipped.
- **Group header** (index pages, outside its card, 12 above it): 36 solid icon tile in the section colour
  (radius 11, white 18 icon), title 18/700, −0.3, ink + count chip (11/700 `#5B6475` on `#E9EBF0`, pill),
  subtitle 13/500 `#667085`.
- **Setting rows:** two columns in one card, 1px `#EEF0F3` dividers between rows and columns, an empty cell
  when the count is odd; a group with one setting spans the full width. Row padding 16/18, gap 14: 40 icon tile (radius 12, section tint fill and stroke, 19
  icon in the section's deep colour), title 14/600 `#101828`, description 12/500 `#667085` at 1.45, chevron
  16 `#98A2B3`. A role badge sits beside the title (neutral `#F3F4F7`, lock 10, 11/600 `#5B6475`); a status pill
  ("Incomplete", "Not set") sits before the chevron when the app shows one.
- **Form card:** header padding 20/24/18/24 — 36 tint icon tile (radius 11) in the page's section colour,
  title 16/700, −0.2, subtitle 13/500 `#667085`; body padding 0/24/24, gap 16; fields in a row 14 apart. Two
  short cards may share a row and share its height.
- **Jump pills:** 38 high pills, 8 apart, padding 0/16/0/14, one per group the viewer can see; each jumps to
  its group and the group in view is lit. No "All settings" pill and no counts — counts live on group
  headers. Lit: black-green `#08150F` fill, 8px section dot, 13/600 white label. Others: white, `#E6E8EE`
  border, 8px section dot, 13/600 `#344054` label.

## Fields and buttons

- **Field:** label above, 13/600 `#344054`, required `*` 13/700 `#E11D48`, "Optional" 12/500 `#667085`.
  Input 44 high, radius 12, white, `#DDE1E8` border, input shadow; value 14/500 `#101828`, placeholder
  `#667085`; optional 16 leading icon `#98A2B3`; select chevron-down 16; unit suffix chip (12/600 on `#F3F4F7`,
  radius 8). Help line 12/500 `#667085`.
- **Locked field:** fill `#F6F7F9`, no shadow, value `#667085`, a lock icon instead of the chevron, help line
  led by a 13 lock icon `#98A2B3` with the app's reason.
- **Textarea:** 88 high, padding 12/14, line height 1.5; "N characters left" right, 12/500 `#667085`.
- **Toggle row:** `#F6F7F9` panel, radius 14, padding 14/16; title 14/600, help 12/500; switch 44×26, on
  `#049A54` with a white 20 knob.
- **Buttons:** main button brand green `#037741` (hover `#02532D`), radius 14 (12 inside cards), 44 high in headers and 40 in
  cards, 14/600 white label and icon, primary shadow — one per
  page, named for the next step; the top bar's "Add new" is the shell's own. Other card actions are
  secondary: `#F6F7F9`, `#E6E8EE` border, 13/600 `#344054` label and icon. On dark surfaces: white button
  with ink label. Small row action: 30 high, radius 9, brand green, 12/600 white.

## Featured card

One per page. The Settings banner: radius 24, padding 28, gap 22, linear gradient 120° `#08150F` →
`#01361D` (60%) → `#02532D`, featured shadow; a 420 radial green glow `#049A5459` → transparent at the top
right with two hairline rings (`#FFFFFF14`, `#FFFFFF0D`). 64 logo tile (radius 18, gradient `#049A54` →
`#037741`, white 30 leaf, green glow); eyebrow 11/700, letter-spacing 1, `#A3B3C2`; name 28/800, −0.8, white;
meta 14/500 `#B8C4D0`; white button right. Fact chips: four equal, radius 14, fill `#FFFFFF0F`, stroke
`#FFFFFF1A`, padding 12/14; label row 14 white (70%) icon + 11/600 `#93A3B4`; value 13/600 white. On record pages
the profit card (job, quote) and the balance-due card (invoice) take this featured style — to design in Part 2.

## Rail cards

- **Account:** 56 avatar (green gradient, 3px white ring), "SIGNED IN AS" 11/700 `#667085`, name 17/700, green
  role pill (`#D7F5E5`, crown 11, 11/700 `#02532D`); two full-width secondary buttons stacked 8 apart.
- **Figure card** (Communication Balance): 28 tint icon box in the section colour, eyebrow 11/700, letter-
  spacing 0.8, `#667085`; figure 34/800, −1, ink; two lines 12/500 (`#5B6475`, then `#667085`); full-width
  secondary button.
- **Status list** (Setup status): header 16/700 + a red chip counting only the items the owner must act on ("1 to do"); rows padding 12/20 with a top divider —
  34 neutral icon tile (`#F3F4F7`, `#344054` icon), title 13/600, text 12/500 `#667085`; right side a green
  30-high action or a status pill (tint fill, 6 dot, 11/700 status colour).
- **Preview** (What customers see): card fill fades `#F4F5F7` → white; green "Live preview" pill; inside, a
  white document (radius 14, `#E6E8EE` border, shadow y12 b24 `#1018281A`, padding 18) showing the logo,
  name, record chip in its record colour, tagline, contact rows with 13 `#667085` icons, and three
  `#EEF0F3` skeleton lines.
- **Where this is used:** rows padding 11/20 with top dividers; 32 tile (radius 10) in the record colour of
  what it affects; title 13/600, text 12/500.

## Save bar

Floating black-green `#08150F` bar centred over the content column: 720 wide, 64 high, radius 20, padding 0/10/0/20, Save bar
shadow. Left: 28 circle `#F59E0B26` with an 8 `#FBBF24` dot; "You have unsaved changes" 14/600 white over
"Nothing is saved until you press Save." 12/500 `#8A96A8`. Right: Cancel (44 high, radius 14, `#FFFFFF14`,
`#FFFFFF1F` stroke, 14/600 `#E5E9F0`) and Save (main button: `#037741`, white check 16 and 14/700 label, primary
shadow). It appears exactly when the shared save rules say the bar shows; Jafar approved the two text lines
2026-10-13. Full-page forms show the bar all the time: while nothing has changed it takes a resting state
with Save disabled (to draw on the design-system page).

## Record page structure

From the earlier family, approved by Jafar 2026-10-13 ("Looks good, continue"). Layout, order and sizes
stand; old token names (`$color-…`) map to § Palette and § Colour rule when the job, quote and invoice
screens are restyled — the primary button becomes brand green with ink text, the record's own pill and track take its record
colour, "now" is brand green.

- **Header card:** padding 24/28/0/28. Row 1: status pill (record colour, pill, 7px dot, 12/600) + record
  number 12/600, letter-spacing 0.6, secondary + 3px dot + record kind 12/500; right: 40×40 history button,
  40-high "More ⌄", then the primary button named for the next step. Title 32/700, −0.8, 18 below row 1.
  Meta row: 28 client avatar + name 14/600; icon-15 + 14/500 secondary facts 16 apart; quick contact buttons
  right (34 circles, bordered).
- **Lifecycle track:** the same five steps on every work record — Request, Quote, Job, Invoice, Paid — each
  page lighting its own; a done step's sub-line says when ("Approved Sep 28"), the current one what it waits
  on ("Waiting on David", "Due in 7 days"). Five equal steps, 6 apart, 24 above and below; 6px pill bars;
  label 13/600 with a check-13 when done or a 7px dot when current; sub-line 12/500, the current one green.
- **Key facts strip:** top divider, padding 18/0/22; four equal facts with 1px dividers and 20 side padding;
  each a 36 icon tile, label 12/500 secondary, value 14/600. Facts that live nowhere else on the page, plus
  the record total. Editable facts (an invoice's terms and dates) end the strip with a 32 bordered pencil
  button instead of a separate section.
- **Lists of dated work:** date tile 52×56, radius 12, bordered — weekday 10/700, letter-spacing 0.6, day
  20/700; today's tile filled brand green `#037741` with a white day. Title 15/600, time 13/500 secondary, note 12/500
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
  circle (done filled `#049A54` with a white check, waiting with an hourglass, to-do a 1.5 outline), label
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

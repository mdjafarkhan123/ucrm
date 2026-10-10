# Botanical v3 reference and starter guidance

Visual direction approved by Jafar on 2026-10-10. Extracted from the unchanged selected reference on
2026-10-11. This is a starter guide for the redesign campaign, not approval to implement every illustrated
control or to restyle the existing app.

## Preserved baseline

The canonical preview is `/demo/job-details/index.html`, in `static/demo/job-details/`.
Its source revision is **faeccae3b021ab763c0406d989b2aca0d25ba15a**. Git preserves the complete HTML,
SCSS, compiled CSS, JavaScript and illustrations at that revision; use that revision for comparison even
if the preview changes later. For example, inspect a baseline file without changing the working folder:

```sh
git show faeccae3b021ab763c0406d989b2aca0d25ba15a:static/demo/job-details/styles.scss
```

Reference captures, Chromium, device scale 1, populated default state:

| Viewport | First screen | Whole page |
| --- | --- | --- |
| 1440 × 900 desktop | [Desktop](1440-top.png) | [Desktop full page](1440-full.png) |
| 390 × 900 phone | [Phone](390-top.png) | [Phone full page](390-full.png) |

[Render evidence](render-evidence.json) records the source hashes, final computed styles, viewport sizes
and actual title font. Captures used a local static server serving the same files, without login or app
data. No app journey was changed. Files in the selected demo remain byte-for-byte unchanged.

## Composition

Follow the reference's hierarchy: forest navigation; a restrained cream header; warm canvas; a softly
tinted identity/summary hero; compact section navigation; clear content panels. The colour and spacing
separate jobs, actions and supporting information without giving every section equal emphasis.

At 1440px the sidebar is 242px wide, header 72px high, and page padding is 30px top and 36px on each side.
The content grid has a flexible 762px main column, 24px gutter and 340px supporting column. Panel stacks
use 22px gaps. These are observed reference measurements, not universal layout requirements for every
industry or page. Preserve the relationship of primary work and supporting context when designing new
surfaces, rather than copying the entire job page.

At 390px the page has 18px side padding and one 354px content column. The hero summary becomes two
columns, photos stack and supporting panels follow the main content. The section strip scrolls within
its container. Both captures have document width equal to viewport width. This does not establish full
phone usability: the reference hides sidebar navigation without a replacement menu, and narrow rows
and financial tables need later focused review. Part 3 must provide reachable phone navigation.

## Colour roles

Values below are the final v3 appearance, after all SCSS overrides. Preserve their roles when extending
the system. Accent colour identifies a subject; a status still needs explicit words or an icon.

| Role | Observed value | Use |
| --- | --- | --- |
| Canvas | `#f5f4ef` | Warm page background |
| Main text | `#243d34` | Dark green ink |
| Supporting content | `#52604f` | Notes, row descriptions and metadata; some local text is darker/lighter |
| Sidebar | `#183e33` → `#132e27`, 165° | Forest navigation gradient |
| Selected sidebar item | `#41644c`, inset `#c7de9c` | Active navigation plus visible marker |
| Brand mark | `#d6e6a4` on `#254732` ink | Light botanical brand accent |
| Header | `#fffef9`, bottom border `#e4e7da` | Quiet app header |
| Standard panel | `#fffefb`, border `#e2e6da` | Main content containers |
| Hero | `#edf3e5` → `#f5f7ed` at 60% → `#faf6e9`, 115° | Identity and key summary; border `#dfe6d3` |
| Primary action | `#286b49`, white text; hover `#205b3e` | Main action emphasis |
| Selected section | `#e7efda`, text `#365e34` | Active section navigation |
| Visit surface | `#eaf2f6`, footer `#e3edf1` | Scheduling context; dark blue text |
| Upcoming status | `#e6eff8`, text `#466986` | Explicit “Upcoming” pill |
| Completed status | `#e9f1df`, text `#4e6f32` | Explicit “Completed” pill |
| In-progress badge | `#deedcb`, text `#3f602b`, border `#cedeae` | Job status words and dot |
| Instructions | `#fffcf4`, border `#eadfc7` | Warm field guidance |
| Instruction icon | `#f4e9cd`, ink `#8b713e` | Amber section identity |
| Labor icon | `#e6edf7`, ink `#566f9b` | Blue section identity |
| Notes/expenses icon | `#f3e8dd`, ink `#956b49` | Clay section identity |
| Files icon | `#e2eeea`, ink `#4e7b6b` | Teal section identity |
| Report icon | `#eee8f4`, ink `#7b6496` | Lavender section identity |
| Pending signature | `#faf4e6` footer, `#eadbb8` panel border | Explicit pending state with amber accent |

Use tinted surfaces and small coloured icons purposefully, with dark readable text. Avoid assigning a
different bright fill to every panel. Brand green, financial emphasis and completion green share a
palette in this reference; labels must keep their meanings clear. This extraction is not a contrast audit.

## Typography

The declared stack is `Inter, 'Segoe UI', Arial, sans-serif`. The standalone reference does not load an
Inter font file. Chromium reported **Liberation Sans Bold** for the title in both captures; no web fonts
were registered. Do not describe these screenshots as verified Inter rendering. Selecting or bundling a
font for implementation needs a comparison with this baseline in the relevant demo.

| Role | Final observed size / weight |
| --- | --- |
| Body | 15px / 400, line-height 1.6 (24px) |
| Hero title | 31px / 600, line-height 1.2 (37.2px), letter-spacing −0.9px |
| Section heading | 18px / 600, line-height 1.6; letter-spacing −0.3px |
| Visit/customer subheading | 16px / 600 |
| Main row content | Usually 15px / 600 for emphasized names |
| Supporting details | Usually 13px / 400 |
| Button and section link | 14px; buttons 600, links 500 |
| Sidebar links | 15px / 500 |
| Hero metrics | 27px / 550; scheduled date is a local 18px exception |

The cascade contains deliberate local exceptions: the first upcoming visit pill computes to 14px,
although the general status-pill rule is 13px. Do not flatten these into one claimed universal token.
The CSS requests intermediate weights such as 550; installed fallback font faces determine the actual
glyph rendering. Future app implementation must respect the app's rem convention rather than copying
standalone pixel values into a differently scaled root.

## Spacing, shape and surfaces

Use measured values as the starting reference; there is no demonstrated complete spacing scale yet.
Common panel content padding is 22–24px. The hero uses 24px top and 25px side padding on desktop, 20px
top/sides on phone. Section icons are 30px squares with 8px corners and 17px glyphs.

Standard panels have 12px corners, a 1px border and a very faint shadow
`0 3px 12px #34483304`. The hero has 15px corners. Buttons use 8px corners and 9px × 13px padding,
with minimum height 42px; text and icons can make their actual height larger. The primary button adds
`0 3px 6px #286b4914`. The section strip has 9px corners; its inner links use 6px. Badges and status
pills use 20px corners. Quiet borders and surface changes provide most separation; shadows stay subtle.

The reference uses panel-contained section headings with small tinted icons. The old design skill's
border-line section-heading appearance does not override this approved direction. Keep existing
save/cancel behaviour and component reuse constraints when the later implementation is planned.

## States and boundaries

The reference demonstrates populated panels, selected navigation, upcoming/completed visits, a pending
signature, default/hover primary buttons and a global 3px `#8ab79c` focus outline with 4px offset for
buttons and links. It includes illustrative editors and photo previews; these are not approvals of a
complete forms, modal or lightbox system. No new component gallery was created in Part 1.

Await focused demo review before standardizing complex forms, field errors, disabled/loading actions,
empty/loading/error pages, menus, comboboxes, calendars, mobile navigation, long-content handling,
dark mode, customer-facing layouts or industry-specific surfaces. Accessibility, text resizing and
outdoor readability remain to be proven. A captured state is evidence of appearance, not workflow
completeness or production readiness.

## Authority and next step

The [approved campaign contract](../../uplift-design-refresh-behavior-contract.md) owns the review and
rollout process. This guide owns the extracted v3 foundations; the source revision and render evidence
make each extraction traceable. Product contracts and verified app behaviour continue to own workflows
and permissions. No new product behaviour or researched interaction is proposed by this extraction.

Part 2 should make the design skill point here, resolve competing old visual instructions, and retain its
screen checks, accessibility and behaviour constraints. Untouched app surfaces retain their current
appearance. New demo revisions need Jafar's review before implementation. Stop after Part 1; do not
create components, a new demo, or live tokens during this assignment.

---
name: design
description: Design system and screen check for any screen, component, styling, or frontend change in this app.
---

# Design System — Agent Instructions

## Authority and transition

For redesign work, read [Botanical v3 starter guidance](../../../docs/design/botanical-v3/README.md)
and the [campaign contract](../../../docs/uplift-design-refresh-behavior-contract.md) first.
The guidance owns demonstrated visual foundations; the contract owns demo review and rollout approval.
Approved product contracts and verified implementation own capabilities and permissions.

Keep this skill and its modules. Update only the necessary parts as focused demos are built and approved.
Use the [alignment register](alignment.md) to distinguish established foundations from patterns awaiting
review. After approval, record the exact demo revision and coverage in permanent guidance, then update
its relevant module before implementation. Keep each value or rule in one authoritative home.

Untouched screens retain their existing appearance. The modules below remain their maintenance reference.
For redesigned portions, approved Botanical guidance takes precedence over old visual values, border-line
headings and `Design/*.jpg` layouts. A pattern missing from Botanical is awaiting approval, not permission
to carry its old appearance into the redesign. Skill edits alone never change app tokens or components.
Retain applicable accessibility, engineering and workflow constraints from existing modules.

## Before Writing Any Code

1. Identify whether the portion is untouched maintenance or an approved redesign. Read its relevant modules
   and, for redesign work, the guidance, approval record and alignment register above.
2. Inspect `src/lib/components` for reuse. Keep Svelte 5, component-local SCSS/BEM and Tabler icons.
3. Follow the campaign's focused demo review before implementing a new design. Resolve conflicting
   behavior sources against the relevant product contract and implementation before changing behavior.

---

## Before Calling a Screen Done

**The screen check scales with the change.** A new screen or layout gets the full check below; a small change
built from existing parts — an added field, option, card, or line — gets one desktop (1440px) and one phone
(390px) screenshot of that spot, fixed until nothing looks off. Use the available browser tools; use Playwright when connected browser control is unavailable.

The full check: look at the real screen the way a picky designer would, not at the code.

1. Open each changed screen in the running app, signed in with a role from the login details in `Login.md`
   that sees the change.
2. Screenshot it at desktop (1440px) and phone (390px) width, in every state the change touches: realistic
   data, empty, loading, error, long names. For untouched screens, add dark mode when the change touches color. Botanical dark mode awaits
   its focused demo approval; report that gap rather than inventing an approved palette.
3. Critique each screenshot against the approved demo and Botanical guidance for redesigned portions,
   or the matching existing blueprint and modules for untouched screens: alignment, spacing, visual hierarchy, crowding, truncation,
   overflow, and anything that reads as a spreadsheet rather than a product.
4. Check keyboard navigation, visible focus, semantic labels, text resizing, contrast, dismissal and
   reachable phone navigation for the affected controls. Check permission differences touched by the change.
5. Fix what the critique found, then screenshot again.

Done when a fresh round at both widths turns up nothing you would fix. Cap it at three rounds, then report
what still looks off. Tell Jafar which screens and states you checked, what you fixed, and the URL to open.

---

## Critical Rules

- **Live tokens and approved foundations have different scopes.** Existing token/module files describe
  the current app. Botanical guidance describes the approved redesign foundations, not deployed tokens.
  When an approved implementation changes a token, update its relevant documentation in the same change
  and check effects on previously migrated surfaces. Material visible shared changes need Jafar's approval.

- **Read related modules together.** Apply their behavior and accessibility constraints; use the authority
  above to select visual rules. Existing `brand.md` precedence applies only to untouched-screen maintenance.

- **Workflow continuity.** Keep the save/cancel rules below during this visual refresh. The older Jobber
  screen-pattern reference contains differing save-bar wording; it does not override these rules. Resolve
  any proposed behavior change with the relevant product contract and Jafar before implementation.

- **Nothing writes without the user pressing a button that saves.** On a detail page that button is normally
  `layout/DetailEditBar.svelte` — tags, notes, attachments and every other widget in the page body stage
  their change and wait for it. Opening a block for editing makes the bar appear at the bottom to save or
  discard everything staged; it is invisible until then. The exception is a modal that manages a child record
  of its own, like a client's property: it carries its own save button, writes when that is pressed, and stays
  out of the page draft. Never build a second save footer, and never leave one on screen permanently.
  `layout/RecordDetailLayout.svelte` is the page shell that carries it. Full-page create and edit forms keep
  their always-visible bar from `RecordFormLayout`; both use `layout/StickyActionBar.svelte` underneath.

  **Opening a block and changing something are two different things**, and the bar owns what each one means
  so every detail page behaves identically. A page reports both facts through `RecordDetailLayout` —
  `editing` for blocks that are open, `dirty` for blocks whose value really differs from what is saved — and
  never decides for itself when the bar shows. Open shows the bar, because Cancel is the only way back out of
  an editor and a block must never trap the user in edit mode. Save stays disabled until `dirty`, so it never
  offers to write a change nobody made. An "Unsaved" badge on a block follows `dirty`, not `editing`.

  That bar is **pinned, not sticky.** `AppShell` publishes `--shell-content-left`, `--shell-content-right`
  and `--shell-edge` so it lines up with the content column and follows the sidebar when it collapses, and it
  measures itself to reserve room at the end of the page. Do not "fix" it back to `position: sticky` — the
  bar is always the last child of its container, so sticky has no room to float through and strands it at the
  very bottom of a long page where nobody scrolls.

  A widget that stages rather than writes reports what is waiting to its page and exposes a save and a
  discard, the way `collaboration/AttachmentsCard.svelte` does with `onPendingChange`, `saveAll(id)` and
  `discardChanges()`. Anything a page's `$effect` calls that way must be wrapped in `untrack`, or the
  widget's own writes come back as dependencies and the page locks up with `effect_update_depth_exceeded`.

- **Photos show as photos.** Image attachments render as a thumbnail grid and open `ui/Lightbox.svelte`
  (arrows, arrow keys, filmstrip, counter, download, Escape); files with nothing to preview keep a list row.
  Never draw a photo as a grey file-type icon, and never point an `<img>` at a presigned storage link — those
  expire in minutes. Images stream from `GET /api/attachments/[id]/view`, with `?size=thumb` for the small
  copy the browser made at upload.

- **Titled blocks:** retain `SectionBlock` on untouched surfaces. For redesigned portions, follow the
  approved panel-contained headings in Botanical guidance and inspect existing components for reuse or
  extension. Preserve appropriate `fieldset`/`legend` semantics for grouped inputs and heading hierarchy.

- **Tokens are NOT Tailwind classes.** Colors are semantic CSS custom properties: `var(--color-bg-surface)`, `var(--color-border)`, `var(--color-text-primary)`, `var(--color-brand)`, `var(--success-solid)`, etc. See `colors.md` for the full contract.

- On untouched surfaces, dark mode is **automatic** via `_theme.scss` (mirrors the app's `dark-theme-tokens` mixin). Never manually swap color values.

- Toggle: set `data-theme="dark"` on `<html>` (explicit in-app choice); OS `prefers-color-scheme` is respected when no explicit choice is set.

- **Every interactive element needs hover, focus, and disabled states** — defined in the relevant module.

- **Use semantic HTML:** proper heading hierarchy (`h1`→`h6`), `<button>` for actions, `<a>` for navigation, ARIA attributes where needed.

## Module Index

### Existing foundation modules (scope governed by Authority and transition)

- [brand.md](brand.md) — Brand
- [colors.md](colors.md) — Color
- [typography.md](typography.md) — Typography
- [layout.md](layout.md) — Layout
- [radius.md](radius.md) — Radius
- [shadows.md](shadows.md) — Shadow
- [borders.md](borders.md) — Borders

### Core Components

- [buttons.md](buttons.md) — Button
- [button-group.md](button-group.md) — Button Group
- [cards.md](cards.md) — Card
- [section-block.md](section-block.md) — Section Block
- [inputs.md](inputs.md) — Input
- [alerts.md](alerts.md) — Alert
- [badges.md](badges.md) — Badge
- [lists.md](lists.md) — List
- [avatars.md](avatars.md) — Avatar
- [icon-shapes.md](icon-shapes.md) — Icon Shape
- [accordion.md](accordion.md) — Accordion
- [dropdown.md](dropdown.md) — Dropdown
- [modals.md](modals.md) — Modal
- [tabs.md](tabs.md) — Tabs
- [tables.md](tables.md) — Table
- [pagination.md](pagination.md) — Pagination
- [sidebars.md](sidebars.md) — Sidebar
- [radios-checkboxes-toggle.md](radios-checkboxes-toggle.md) — Radio, Checkbox,
- [tooltips-popovers.md](tooltips-popovers.md) - Tooltips and popovers
- [content.md](content.md) - Content grid and layout system

### CRM-Specific Components

- [status-indicators.md](status-indicators.md) - Job/project status, pipeline stages, priority |
- [stats-cards.md](stats-cards.md) - KPI metric cards, trend indicators, featured stats
- Charts and timelines — Botanical guidance awaits focused review; no data-display module exists yet.

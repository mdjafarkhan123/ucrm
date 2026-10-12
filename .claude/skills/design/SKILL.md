---
name: design
description: Route every screen, component, styling or frontend task to its design guidance and run the shared screen check.
---

# Shared design workflow

## Choose the presentation first

1. For existing-app maintenance, load [Classic](../design-classic/SKILL.md). Preserve the actual screen.
2. For Botanical work, including private demos, load [Botanical](../design-botanical/SKILL.md).
   A redesign request alone does not switch the live app. Classic remains live until approved rollout.
3. When work spans both designs, load each separately and verify each affected presentation. For an
   unspecified new presentation, resolve the intended design with Jafar before choosing visual rules.
   Control Room, login and customer-facing surfaces retain their current appearance in the first release.

The [CRM design-system agreement](../../../docs/crm-design-system-behavior-contract.md) and its
[approved foundation](../../../docs/crm-theme-foundation-behavior-contract.md) own current theme scope,
safe switching and selected-only delivery. Earlier selectable-design work supplies reusable evidence.
Presentation skills own appearance; product contracts and verified implementation
own records, capabilities and permissions. Share behaviour rather than copying it into design pages.

Before code, inspect `src/lib/components` for reuse. Use Svelte 5, component-local SCSS/BEM, Tabler icons,
semantic HTML and semantic design tokens. Preserve existing loading/cache/preload rules. Every interactive
control needs hover, focus and disabled states. A skill edit alone never changes application assets.

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

## Shared workflow constraints

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

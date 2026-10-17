# Record page behaviour

Rules for record detail pages, create/edit forms and attachments. Read before building or changing a detail
page, its save bar, a staging widget, or image attachments.


- **Workflow continuity.** Keep the save/cancel rules below during any visual change. The older Jobber
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

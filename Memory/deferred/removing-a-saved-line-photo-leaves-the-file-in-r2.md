# Removing a saved line photo leaves the file in R2

- **Priority:** P1


- **Campaign:** `quotes` (Part 2, found 2026-08-20).
- **Reason:** Jafar was told on 2026-08-20, called it a serious storage leak, and chose to fix it later —
  deferred by his decision, not because it is small.
- **What is wrong:** `discardIfOrphaned()` in `src/lib/components/quotes/RequestPricingBlock.svelte` only
  deletes an attachment the current editing session uploaded, which is right — it must never delete a photo
  another tab is using. But once a photo has been saved onto a line, removing it later clears
  `image_attachment_id` and deletes nothing: the `attachments` row and the R2 object both survive with
  nothing pointing at them. Confirmed by uploading a photo, saving, removing it, saving again — the row was
  still there.
- **Reactivation trigger:** Jafar asks for it — he has already agreed it needs doing. Otherwise the first
  of: noticeable R2 cost, an orphan audit, or Quote-side line photos repeating the same shape.
- **Prerequisites:** Decide who owns the cleanup — the save command (it already knows which attachment ids
  the request dropped) or a sweep job. A Request-side delete must never touch a converted Quote's frozen
  line, which deliberately holds the same id without an FK.
- **Checkpoint:** `src/lib/components/quotes/RequestPricingBlock.svelte`, `public.request_pricing_lines`.


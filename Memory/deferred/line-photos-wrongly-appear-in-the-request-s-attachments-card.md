# Line photos wrongly appear in the request's Attachments card

- **Priority:** P2


- **Campaign:** `quotes` Part 2, found in the Session 9 browser pass and confirmed a bug by Jafar on
  2026-08-20. Deferred by Jafar in the same breath, to fix after the current Quotes path.
- **What is wrong:** a photo attached to a pricing line is stored as an attachment on the request, so the
  Attachments card lists it alongside the documents somebody deliberately filed there. Jafar's words: it
  behaves "like a phone gallery, pulling up all phone photos". The line photo is part of the line, not a
  request document, and the office should not have to scroll past it — or worse, delete it from there and
  silently strip a priced line.
- **Where it comes from:** `RequestPricingBlock.svelte` uploads through the shared attachment path, which
  writes `attachments` with `entity_type = 'request'` and `entity_id = <the request>`. `AttachmentsCard`
  then lists every attachment for that entity with no way to tell the two kinds apart.
- **The likely fix:** give the attachment a role, so a line photo is distinguishable from a filed document,
  and have the Attachments card list only documents. Needs a schema decision and therefore its own approved
  packet; do not guess at it inside another part.
- **Reactivation trigger:** Jafar says so, or Part 3+ touches line photos or the Attachments card again.
- **Prerequisites:** Schema approval like any migration; `supabase-postgres-best-practices` first. Whatever
  ships must keep the Part 2 behavior that a cancelled upload is deleted and a saved one survives.
- **Checkpoint:** `src/lib/components/quotes/RequestPricingBlock.svelte`,
  `src/lib/components/collaboration/AttachmentsCard.svelte`, `public.attachments`.


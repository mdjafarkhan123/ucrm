# Client documents drop line photos and need a completeness pass

**Why deferred:** Raised by Jafar on 2026-09-07 at the end of an Invoices session, as its own piece of work
across both Quote and Invoice. Too big to fold into Invoices Part 5c.

**Reactivates when:** Jafar picks it up. Independent of the Invoices campaign — no dependency either way.

**What Jafar asked for**

- A line item's photo must appear on the client-facing document, not only the staff table, and clicking it
  opens the large preview (`ui/Lightbox.svelte`), the convention the design skill already sets for photos
  everywhere else. Without it the document reads modern but not professional.
- Then a **research pass on what a professional Quote and Invoice actually carry** — settle what is missing
  today rather than fixing one field at a time. Quantity is explicitly in scope: if the research says a
  document should show it, put it back.
- Applies to **both Quote and Invoice** client views.

**Already known, so the future decision does not restart**

- `CustomerInvoiceDocument.svelte` has no photo support at all — `CustomerInvoiceLine` in
  `src/lib/invoices/customer-document.ts` does not carry `image_attachment_id`, so the read must change
  before the component can. The staff table (`quotes/ProductsAndServicesBlock.svelte`) already draws line
  photos and is the pattern to follow.
- **The blocking question is access, and it is auth-adjacent — confirm with Jafar before touching it.** A
  client viewing their document is not logged in, while images stream from
  `GET /api/attachments/[id]/view?size=thumb`, which serves staff. A client must see that one photo without
  gaining anything else. Never point an `<img>` at a presigned storage link — those expire in minutes.
- Jobber does show line-item images to clients in Client Hub (`jobber-03` line 145), so the behavior is
  grounded; it is a Grow-plan feature there.
- Quantity was deliberately removed from **progress bills only** on 2026-09-07, because those lines are one
  lump priced at a stage's share and a per-unit reading of them is false — see the Invoices `NOW.md`. Any
  research that restores quantity must not restore it there without changing how those lines are stored.

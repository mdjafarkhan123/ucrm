# No image on a price list item

- **Priority:** P3


- **Campaign:** `quotes` (Part 2, deferred 2026-08-20).
- **Reason:** Jafar's call. Jobber's Add Product / Service dialog has an image dropzone; ours ships without
  one so Part 2 closes on the schema it already has.
- **What is missing:** `catalog_items` has no image column at all. Adding one means a migration, extending
  the `attachments` `entity_type` check with a catalog value, an upload flow inside the dialog, and a
  decision about whether picking an item copies its image onto the line the way name/description/price
  already are.
- **Reactivation trigger:** Jafar asks for item photos, or the Products & Services settings screen gets
  built — that screen is where an item's own photo really earns its place.
- **Prerequisites:** Schema approval like any other migration; `supabase-postgres-best-practices` first.
- **Checkpoint:** `src/lib/components/quotes/CatalogItemDialog.svelte`, `public.catalog_items`.


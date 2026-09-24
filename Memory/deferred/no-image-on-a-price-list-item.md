# No image on a price list item

- **Priority:** P3


- **Campaign:** `quotes` (Part 2, deferred 2026-08-20). Re-confirmed still deferred, not dropped, by Jafar
  2026-09-22 while scoping Files and Media Part 6 ("don't delete this feature, need to add later").
- **Reason:** Jafar's call. Jobber's Add Product / Service dialog has an image dropzone; ours ships without
  one so Part 2 closes on the schema it already has.
- **What is missing:** `catalog_items` has no image column at all. Adding one means a migration, an upload
  flow inside `CatalogItemDialog`, and a decision about whether picking an item copies its image onto the
  line the way name/description/price already are. Build it on the File Manager catalog
  (`public.files`/`file_links`, origin `catalog_item`) now that it exists — not the legacy `attachments`
  table this note originally assumed.
- **Reactivation trigger:** Jafar asks for item photos, or the Products & Services settings screen gets
  built — that screen is where an item's own photo really earns its place.
- **Prerequisites:** Schema approval like any other migration; `supabase-postgres-best-practices` first.
- **Checkpoint:** `src/lib/components/quotes/CatalogItemDialog.svelte`, `public.catalog_items`.


# Job Visit override-pricing line photo removal doesn't Trash the dropped photo

- **Priority:** P3
- **Why postponed:** Narrower surface than the main bug (only visits with a price override enabled); found
  while fixing `removing-a-saved-line-photo-leaves-the-file-in-r2` (2026-09-27).
- **What's true now:** `JobVisitDialog.svelte` runs `ProductsAndServicesBlock` with `alwaysEditing={pricingEditable}`
  and reads the draft via `onDraftChange`, never calling `openEdit()`/`save()`. The Save/Trash-diff fix added
  to `ProductsAndServicesBlock.svelte`'s `save()` only runs on that internal edit-in-place path (used by
  Request, Quote, Job, and Invoice detail pages), so a previously-saved visit-override line photo that's
  removed and saved through this dialog still leaves its File un-trashed.
- **Reactivate when:** touching JobVisitDialog's pricing save flow again, or if visit-line photo storage waste
  is reported.
- **Constraint:** fix needs the same entrySavedFileIds-diff approach, computed from the dialog's own saved
  pricing snapshot since this path never calls openEdit().
- **Pointer:** src/lib/components/jobs/JobVisitDialog.svelte, src/lib/components/quotes/ProductsAndServicesBlock.svelte.

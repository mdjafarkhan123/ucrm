# Removing a saved line photo leaves orphaned storage

- **Priority:** P1
- **Why postponed:** Clearing a saved line's attachment id leaves both its attachment row and R2 object; Jafar deferred ownership of cleanup.
- **Reactivate when:** Jafar resumes it, storage cost appears, or line-photo handling is extended.
- **Constraint:** Cleanup must not delete a file still referenced by another tab or a converted Quote snapshot.
- **Pointer:** RequestPricingBlock.svelte and public.request_pricing_lines.

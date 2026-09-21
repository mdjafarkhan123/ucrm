# Removing a saved line photo leaves orphaned storage

- **Priority:** P1
- **Why postponed:** Clearing a saved line's attachment id leaves both its attachment row and R2 object; Jafar deferred ownership of cleanup.
- **Reactivate when:** Jafar resumes it, storage cost appears, or line-photo handling is extended.
- **Constraint:** Cleanup must not delete a file still referenced by another tab or a converted Quote snapshot.
- **Pointer:** RequestPricingBlock.svelte and public.request_pricing_lines.
- **Known 2026-09-21:** Deleting on Save is unsafe. Cloned quote drafts, published quote versions and jobs converted from
  them all point at the same attachment row (`on delete set null`), and `DELETE /api/attachments/[id]` removes the row
  and the R2 file outright, so it would blank the photo everywhere it was copied. Needs a "still linked anywhere?" check,
  which is what the Files and Media campaign's one-file-many-links model provides. A stashed attempt exists
  (`git stash list`, "UNSAFE: delete removed saved line photo").

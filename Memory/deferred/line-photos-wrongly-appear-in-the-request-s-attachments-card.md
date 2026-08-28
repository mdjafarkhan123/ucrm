# Pricing-line photos appear as Request documents

- **Priority:** P2
- **Why postponed:** Line photos and filed documents share the same Request attachment identity, so AttachmentsCard cannot distinguish them; fixing it needs schema approval.
- **Reactivate when:** Jafar resumes it or line photos/AttachmentsCard are touched.
- **Constraint:** Preserve cancelled-upload cleanup and saved-line-photo survival.
- **Pointers:** RequestPricingBlock.svelte, AttachmentsCard.svelte, and public.attachments.

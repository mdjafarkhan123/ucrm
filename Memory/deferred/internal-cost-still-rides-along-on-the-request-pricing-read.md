# Internal cost still rides along on the request pricing read

- **Priority:** P1


- **Campaign:** `quotes` Part 2B, deferred 2026-08-20.
- **Reason:** `GET /api/requests/[id]/pricing` returns `unit_cost_minor` and `line_cost_total_minor` to
  anyone in the organization. Nothing displays it, and the catalog side is now properly gated on
  `quotes.view_cost`, but the payload still carries a figure office and sales may not see.
- **What blocks the obvious fix:** the pricing save replaces the whole set and its payload carries no line
  identity, so a redacted read cannot round-trip existing costs — a cost-blind member's save would wipe
  them. The catalog backfill in the PATCH covers new price-book lines only.
- **Reactivation trigger:** the Quote workspace needs the same read, cost appears anywhere in the Request
  line editor, or a member outside owner/admin/finance is given a reason to open pricing.
- **Prerequisites:** decide whether the save payload gains a stable line id (which also unlocks per-line
  diffing) or the write function resolves untouched costs itself.
- **Checkpoint:** `src/routes/api/requests/[id]/pricing/+server.ts` (`LINE_SELECT` and `withCatalogCost`).


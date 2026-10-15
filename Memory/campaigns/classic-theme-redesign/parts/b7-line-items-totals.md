# B7 — line items and totals

**Stage:** Built and checked 2026-10-15 on branch `claude/classic-b7` (worktree `.worktrees/classic-b7`); waiting to
merge. Reservation `82a14a0026d7`.

**Agreement:** Approved `classic.pen` frames: `Products and services card` (`C6XPJG` Quote, `zSKYP` Invoice, `U2bpt`
Job) and `Discount and tax card` (`j8U5l`, `I8b5g`). [Contract](../../../../docs/classic-theme-redesign-behavior-contract.md)
§ Shared building blocks. Jafar (2026-10-15): work only on Classic.

**Built:**
- `ProductsAndServicesBlock`: Classic saved card — "N items and N optional add-ons" under the title, soft header band,
  edge-to-edge rows, add-on chip, discount/tax/total closing the card (new `totals` prop; pages pass the database's
  figures), locked footer with a lock icon and, on quotes, "Client sees every figure / some figures" (new
  `footerNote`, from the saved client-view settings). The editing cards take the soft Classic shell. The table scrolls
  inside the card (`contain: inline-size`), so a phone no longer widens it.
- New `work/AdjustmentRow` and `work/RecordAdjustmentsCard`: Discount and Tax are rows in one "Discount and tax" card
  with plain green Add / Edit / Set tax. `RecordDiscountCard` and `RecordTaxCard` keep their dialogs and write
  logic; only the shell changed. Used on Quote, Job, Invoice and the new-quote form.
- `QuoteSummaryCard`: in Classic it hides the money rows (they now sit in the line-items card) and shows only the
  team-only cost, profit and margin, or nothing.

**Proof:** `vitest` for the block: 6 pass (two new, covering discount, tax and total). Real pages as the owner:
Quote, Invoice and Job at 1440 and 1100 light/dark; Quote at 390; new-quote form add-line (64 × $42 = $2,688.00)
and add 10% discount. Prettier clean; ESLint clean on new files; one older `Set` lint error in the block pre-dates
this work.

**Still different from Pencil (left on purpose):** the Quote rail's featured "Estimated profit" card and the Job
profit card are B6; the edit pencil is still the old plain icon; the saved card shows line photos the frame omits.

**Next:** B6 Job details (profit card replaces the interim "Overview" team-figures card).

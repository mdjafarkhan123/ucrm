# A2 — Quote details (App look)

**Branch/worktree:** `claude/a2-quote-details`, `.worktrees/a2-quote-details`. **Claim:** `b8c74cde1fb3`. **State:** Waiting to merge.

**Built (Pencil `e2gTd`):** header with status, version, history, send action, client row, lifecycle track (new `work/LifecycleTrack`) and facts strip; Products and services with totals and lock line; client message and disclaimer; rail with dark Estimated profit card (new `work/ProfitCard`), Deposit, Discount and tax, Automation, Photos and files, Notes (new `layout/RailRow`). Shared parts extended: SectionBlock, RailCard, NotesPanel, RecordFactsList, WorkRecordHeader, ClientSummaryCard, RecordDiscountCard, RecordTaxCard.

**Checked:** 1440 light and dark, 1100 light, owner login. Fixed the header actions overflowing at 1100 (they now wrap). Save bar behaviour unchanged. Type check, lint and tests NOT run: the lead runs them once for the whole batch.

**Leftovers:** Profit card turns light in dark mode, like the list money cards (open plan question). Broken thumbnail in the test quote is test data. Expect merge conflicts in shared parts with other A2 branches (Invoice, Request, Payment).

# Roadmap — Deferred launch sweep (approved 2026-09-27)

Work the ready deferred tasks (Memory/deferred/) before the first paying client, most urgent first. Each part
is one session. A part's task notes are its spec; delete each note and its INDEX row when fixed. Ask Jafar
any product decision at the part's start, with a recommendation. Opus: Parts 1, 2, 4, 6, 8. Sonnet: 3, 5, 7, 9.

## Parts

1. **Email can silently stop** — Done 2026-09-27 (`32f49eb0`): a missing allowance counts as zero, live-proven.
   Package terms stay deferred until Jafar plans packages (note kept in Memory/deferred/).
2. **Broken things** — Done 2026-09-28. Seat count: send was correct live; the real bug was a cancelled invite
   holding its seat and Team row until the worker ran (fixed in `cancel_team_invitation`). `office-role-cannot-load-client-communication-history`,
   `two-job-billing-reminder-modes-raise-no-reminder`, `full-page-load-hydration-crash-leaves-the-previous-page-on-screen` (investigated 2026-09-27: no leak, not reproducible; parked),
   `tab-selection-read-from-a-stale-page-url`, `board-presentation-and-formatting-are-read-behind-a-settings-permission`,
   `job-payment-schedule-dialog-keeps-a-stale-reconciliation-banner`, `team-seat-count-overshoots-right-after-an-invitation`,
   `review-history-says-sent-for-a-scheduled-request`, `job-visit-override-pricing-photo-removal-not-trashed`,
   `marketing-release-leftovers` (broken campaign now opens fine; its two feature items stay deferred),
   `staff-own-actions-lag-behind-realtime-echo` (fixed; its slow inbox read moved to Part 8).
3. **No fake numbers** — Done 2026-09-28: one shared money read model (`invoice_money_overview`,
   `client_work_summary`, both permission-gated to null rather than a wrong number). Invoices list KPI tiles
   (Outstanding/Overdue/Collected this month) and the client header stats (Lifetime/Open quotes/Active jobs)
   are real; the Requests list's third KPI card was dropped (Jafar's call, matches Jobber's two-card layout).
   Deliberately left deferred: the client page's Work overview/Client schedule sections (bigger build, not a
   rollup -- `client-work-overview-and-schedule-sections-are-empty`) and the Requests list's other two cards,
   found incidentally and not on this part's original list (`requests-new-and-conversion-rate-cards-have-no-real-data-source`).
4. **Fixing money mistakes** — In progress 2026-09-28 (decisions D6–D9 in docs/invoice-behavior-contract.md).
   Slices, in order: 4a void cancellation email — Done `4d96acd1` (`void-invoice-has-no-client-cancellation-email`);
   4b one payment split across several invoices — Done `4d96acd1`; 4c fix payment / mark never received — Done `f6f95e39`
   (4b+4c = `payments-cannot-be-edited-deleted-or-split-across-invoices`); 4d correct an issued invoice with
   payments carried over — DB done, screens WIP `444935b5` (`issued-invoices-cannot-be-corrected-from-the-browser`).
5. **Complete customer documents** — Planned. `client-documents-drop-line-photos-and-need-a-completeness-pass`,
   `line-photos-wrongly-appear-in-the-request-s-attachments-card`, `invoice-email-sends-to-primary-only-not-billing-contact`.
6. **Protect customer history** — Planned. `property-deletion-guarded-once-work-references-a-property`,
   `historical-address-safety-and-property-transfer-between-clients`,
   `client-duplicate-detection-merge-archive-restore-and-audit-history`, `entitytype-covers-only-clients-and-properties`.
7. **Jobber parity** — Planned. `request-list-search-doesn-t-match-client-name`,
   `request-status-filter-matches-the-stored-status-not-the-displayed-one`,
   `quote-composer-has-no-financial-rail-or-proposal-sections`,
   `client-detail-page-still-uses-the-superseded-staging-dialog-edit-shape`, `job-visit-card-backend-fields`,
   `last-communication-rail-card-on-the-client-page`, `no-image-on-a-price-list-item`.
8. **Speed** — Planned; performance-review skill. `get-started-page-weight`,
   `every-entitlement-gated-route-re-reads-the-whole-access-model`, `app-wide-rls-helpers-run-once-per-returned-row`,
   `name-search-across-list-apis-falls-back-to-a-sequential-scan`, `quote-overview-counts-scan-the-whole-tenant`,
   `six-unindexed-foreign-keys-from-the-collaboration-tables`, `a-customer-file-re-resolves-the-whole-quote-document`,
   `app-shell-idle-warmer-downloads-every-routine-route`, `client-photos-are-one-request-each`,
   `list-table-rows-use-goto-instead-of-real-links`, `jafar-panel-organization-tabs-have-no-hover-prefetch`,
   `inbox-read-takes-over-a-second`.
9. **Final live checks** — Planned. `stripe-disconnect-open-checkout-expiry-not-live-tested`,
   `website-chat-realtime-connection-quota-unconfirmed`, `non-admin-email-correction-browser-verification-part-7`.

46 tasks worked; 21 left deferred.

## Left deferred (waiting on the server move, a missing feature, or a reproduction)

The remaining 21 notes stay in Memory/deferred/ untouched.

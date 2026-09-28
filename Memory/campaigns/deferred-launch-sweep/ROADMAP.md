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
4. **Fixing money mistakes** — Done 2026-09-28: void cancellation email, one payment split across invoices, fix payment
   / mark never received, and correct an issued invoice (or rebill a voided one) with payments carried over — all
   browser-checked on Raad LTD. Fixed on the way: replaced/voided bills showed a false balance (`5bd3b498`), and
   the voided-invoice guard blocked rebilling (`20260928190000`, applied straight to the database because the
   Part 7 session's `20260928180000` isn't in this folder yet).
5. **Complete customer documents** — Done 2026-09-28. `line-photos-wrongly-appear-in-the-request-s-attachments-card`:
   already fixed by the Files and Media migration before this part started — the old `AttachmentsCard`/`public.attachments`
   path it described isn't wired to requests any more; `file_links.role <> 'line_photo'` already keeps a line photo off
   the record's own file list. No code change; note closed. `client-documents-drop-line-photos-and-need-a-completeness-pass`:
   researched against Jobber (`jobber-03`/`jobber-05`) — Jobber's own invoice line item has no photo field at all, even
   on its paid plans (photos are a quote-side Grow-plan upsell only); Jafar chose to match that and not build invoice
   photos. Quote line items already carried the photo but had no click-to-enlarge; added the standard `Lightbox`
   (`CustomerQuoteDocument.svelte`) so it matches the convention used everywhere else. Quantity/other line content
   already matches Jobber's own field set (including the progress-bill exception, which lines up with Jobber's own
   `originalCost` concept) — no further completeness gap found. `invoice-email-sends-to-primary-only-not-billing-contact`
   was held for Part 4; Part 4 is Done, so it resumed and shipped: both invoices and quotes now email the client's
   primary address and a separate billing-contact address when one is set, browser-verified on Raad LTD (Greenfield
   Property Group, invoice #35 and quote #44) — both delivery intents submitted, both access links opened their
   document.
6. **Protect customer history** — Planned. `property-deletion-guarded-once-work-references-a-property`,
   `historical-address-safety-and-property-transfer-between-clients`,
   `client-duplicate-detection-merge-archive-restore-and-audit-history`, `entitytype-covers-only-clients-and-properties`.
7. **Jobber parity** — Done 2026-09-28. `request-list-search-doesn-t-match-client-name`
   and `last-communication-rail-card-on-the-client-page` are fixed, browser-verified on Raad LTD, and merged
   into `main` (`0a640513`); their notes are deleted. Found
   incidentally: Jobs and Quotes list search have the same missing-client-name gap Requests had — recorded as
   new deferred note `jobs-and-quotes-list-search-also-misses-client-name.md`, not fixed (out of this part's
   original list). Jafar approved five more slices 7a–7e (request status filter, client edit rewrite, quote
   composer save-on-first-entry, job visit off-series marker, price-list item picture); all five built and
   merged into `main`. 7e's photo carries through everywhere it should (item, price book list and drawer,
   quote line, quote save) but stays a placeholder image because of the known files-processing-worker gap
   (see `Memory/deferred/background-jobs-have-no-production-scheduler-decision.md`) — same as Parts 3, 8A,
   8B. Its deferred note (`no-image-on-a-price-list-item.md`) is deleted.
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

# Roadmap — Deferred launch sweep (approved 2026-09-27)

Work the ready deferred tasks (Memory/deferred/) before the first paying client, most urgent first. Each part
is one session. A part's task notes are its spec; delete each note and its INDEX row when fixed. Ask Jafar
any product decision at the part's start, with a recommendation. Opus: Parts 1, 2, 4, 6, 8. Sonnet: 3, 5, 7, 9.

## Parts

1. **Email can silently stop** — Done 2026-09-27 (`32f49eb0`): a missing allowance counts as zero, live-proven.
   Package terms stay deferred until Jafar plans packages (note kept in Memory/deferred/).
2. **Broken things** — Done 2026-09-28: eleven notes fixed or closed, including a cancelled invite holding its
   seat (`cancel_team_invitation`); the hydration crash was investigated, not reproducible, and parked.
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
5. **Complete customer documents** — Done 2026-09-28. Line-photo note was already fixed by Files and Media;
   Jafar chose to match Jobber (no invoice line photos); quote line photos gained the standard `Lightbox`;
   invoices and quotes now also email a separate billing contact, browser-verified on Raad LTD.
6. **Protect customer history** — split 2026-09-28; two of its four notes were obsolete. 6A **Done**
   (`95680990`): closed `entitytype-covers-only-clients-and-properties` and
   `historical-address-safety-and-property-transfer-between-clients` (both already satisfied by shipped work;
   property transfer dropped — Jobber has no such feature), and gave the finance role real invoice access
   (`20260928240000`, applied and verified live). 6B **Done** (`ce48dfa2`) — client archive + restore, browser-verified 2026-09-28 (archive, Archived
   filter, restore, refusal listing open work). 6C **Planned** —
   property cascade delete, the destructive one; covers
   `property-deletion-guarded-once-work-references-a-property`. Read the part note before either.
7. **Jobber parity** — Done 2026-09-28 (`0a640513`). Request-list client-name search and the client page's
   last-communication card fixed and browser-verified; plus five Jafar-approved slices 7a–7e (request status
   filter, client edit rewrite, quote composer save-on-first-entry, job visit off-series marker, price-list item
   picture). 7e's photo carries through everywhere but renders as a placeholder because of the known
   files-processing-worker gap (`Memory/deferred/background-jobs-have-no-production-scheduler-decision.md`) —
   same as Parts 3, 8A, 8B. Found incidentally and left deferred: Jobs and Quotes list search have the same
   client-name gap (`jobs-and-quotes-list-search-also-misses-client-name.md`).
8. **Speed** — Done 2026-09-28, merged to `main`: 10 of 12 notes fixed and measured (sign-up page ~8 MB →
   531 kB; name search on a 50k-client tenant 240 → 3 ms via trigram indexes; list rows and the Jafar
   Communications tab prefetch on hover; a closed tab no longer mounts or loads — shared `TabPanel`). Two moved
   to Part 11. File Manager search split off to `file-manager-search-cannot-use-an-index`.
9. **Final live checks** — Done 2026-09-28. Non-admin email correction: office member's email changed,
   round-tripped and changed back on Raad LTD, both audited. Website Chat ceiling re-deferred to the staging
   VPS (note updated). Stripe disconnect, on Raad's sandbox by Jafar's choice: a fresh customer checkout
   (invoice #35) plus 6 stale ones all went `failed`, the connection row is gone, and the customer's Stripe
   page stopped showing the business. **Raad needs its sandbox key re-pasted** (Settings → Payments) by Jafar.
10. **Merge duplicate clients** — Planned (Opus), split out of Part 6 with Jafar's approval on 2026-09-28
    because moving every child row from one client to another is the riskiest write in the sweep. Jobber ships
    this as a first-class "Merge Clients" action in the clients list's More Actions menu, beside Import and
    Export. Covers the merge half of
    `client-duplicate-detection-merge-archive-restore-and-audit-history`, plus the audit history; today there is
    only create-time duplicate warning by `ilike '%term%'`, capped at 5 rows.
11. **Speed on client pages** — Planned (Opus; performance-review). `client-photos-are-one-request-each`
    (Jafar: follow the industry pattern — batched short-lived signed URLs) and
    `app-wide-rls-helpers-run-once-per-returned-row`. Both waited on Part 6's client work; only 6C's property
    files are still in flight.

46 tasks worked; 21 left deferred.

## Left deferred (waiting on the server move, a missing feature, or a reproduction)

The remaining 21 notes stay in Memory/deferred/ untouched.

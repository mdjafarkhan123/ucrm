# Quotes Roadmap

| Part | Outcome | Status | Dependencies | Packet | Completion gate |
| --- | --- | --- | --- | --- | --- |
| 1 | Quote behavior contract and data-architecture approval | Complete 2026-08-19 | Approved campaign plan and live Jobber tour | `docs/quote-behavior-contract.md` | Jafar approved lifecycle, ownership, money/version/deposit rules, and proposed schema/RLS/API boundaries before implementation. |
| 2 | Pricing foundation and Request carry-forward | Complete 2026-08-20 | 1 | `parts/02-pricing-and-request-carry-forward.md`; `parts/02b-price-book-drawer.md` | Catalog and Request pricing produce exact tenant-safe Quote snapshots; the visible Price book supports safe multi-add and custom-line workflows; calculations, indexes, conversion idempotency, and browser checks pass. |
| 3 | Staff Quote workspace | Complete; browser gate ran in 4D except three checks now in the deferred index | 2 | `parts/03-staff-quote-workspace.md` | Authorized staff can create direct or Request-backed Quotes and use the list, composer, detail, numbering, filters, statuses, existing Notes/Attachments, and a truthful read-only Quote summary without contradictory truth. |
| 4 | Professional proposals and immutable versions | Closed 2026-08-21 | 2–3 | `parts/04-professional-proposals-and-versions.md` | Optional add-ons, named fixed/percentage discount, one named tax rate, approved proposal sections, client visibility, and immutable version foundations preserve historical documents and exact totals. Packages were removed again on 2026-08-21. |
| 5 | Secure delivery, customer decision, and useful Quote actions | Closed 2026-08-21 — all four subparts complete | 3–4 | See subparts | Secure sharing, meaningful view, customer decisions, signatures, offline decisions, and status-aware Quote utilities are trustworthy and version-bound. |
| 5A | Staff publication and lifecycle | Complete 2026-08-21 | 3–4 | `parts/05a-staff-publication-and-lifecycle.md` | Staff can publish a draft into the next version, revise a published version, and record an offline decision; publishing twice makes one version; the header names only moves the database would allow. |
| 5B | Secure customer link and decision page | Complete 2026-08-21 | 5A | See subparts | Recipients, hashed link tokens, the rendered customer document, Preview as client, first meaningful view, decisions, expiry, rotation, and rate limits. |
| 5B1 | Secure access foundation and one customer renderer | Complete 2026-08-21 | 5A | `parts/05b1-secure-access-and-customer-renderer.md` | One version-bound recipient link securely renders only frozen customer data; staff Preview uses the same renderer with inert decisions; print/save PDF uses its print layout. |
| 5B2 | Public view tracking and customer decisions | Complete 2026-08-21 | 5B1 | `parts/05b2-view-tracking-and-customer-decisions.md` | First meaningful view, Approve / Request changes, enforced expiry, rotation, idempotency, and per-IP/per-token limits are secure and race-tested. |
| 5C | Signatures | Complete 2026-08-21 | 5B | `parts/05c-signatures.md` | Typed and drawn signatures on the customer page, an in-person pad for staff, each bound to one version and document hash and invalidated by material revision. |
| 5D | Quote utilities and complete status-aware menu | Complete 2026-08-21 | 5B–5C | `parts/05d-quote-utilities.md` | Staff can create a similar draft, archive/restore, safely delete only eligible unused drafts, preview, print/save PDF, and see only actions their permission and the Quote's state can actually complete. Email and Job conversion remain dependency-gated rather than simulated. |
| 6 | Deposits and payment schedules | Closed 2026-08-22 — 6A, 6B, 6C all complete and browser-verified | 2, 4–5 | See subparts | No-deposit versus required fixed/percentage deposit rules recalculate correctly, required deposits gate readiness, approved offline recording is supported, and money remains traceable for later Job/Invoice allocation. No fake online processing ships. |
| 6A | Deposit schema and calculation | Complete 2026-08-21 | 2, 4–5 | `parts/06a-deposit-schema-and-calculation.md` | `quote_version_schedule_items` and `quote_versions.deposit_type`/`deposit_required_minor` exist; the calculator prices deposit-only and milestone-first-installment deposits, fixed or percentage, recalculating with the live add-on selection and capped at the total; Publish/Revise/Create Similar all carry the deposit shape forward; pgTAP plan 35 passes against remote. |
| 6B | Staff deposit configuration and offline recording | Closed 2026-08-21, browser-verified | 6A | `parts/06b-deposit-configuration-and-recording.md` | The `QuoteDepositCard` right-rail dialog (Deposit only vs. Payment schedule, following `QuoteTaxCard`'s pattern, folding record/reverse status into the same card), the `quotes.record_deposit` permission, and record/reverse offline-deposit commands. Milestone "installments sum to the total" validation lands here, at save time. |
| 6C | Readiness gating and customer-facing display | Closed 2026-08-22, browser-verified | 6B | `parts/06c-readiness-gating-and-customer-deposit-display.md` | `ready_for_job` derived label wired into approval and the (still Jobs-gated) Convert-to-Job check; the secure customer page shows the required deposit with an "arrange with your contractor" message, never a payment control, following the contract's pre-Payments rule. |
| 7 | Quote-backed Sales Pipeline completion | Pending | 5 and relevant Part 6 truth | Resume `sales-pipeline` Part 5 | Request conversion replaces the Request card with a Draft Quote card; protected actions drive real Quote transitions; approval wins atomically; Pipeline Part 5 gates pass. |
| 8 | Terminal Job handoff and final audit/manual | Pending | 1–7 and Jobs foundation | Create when active | One idempotent conversion copies approved scope into Job-owned history, Quote stays Converted terminally, full desktop/security/performance checks pass, and the product manual reflects the shipped journey. |

## Standing decisions

- Quotes may be created directly or by converting a Request.
- Request pricing is copied into quote-owned snapshot rows; Request and Quote do not share mutable line rows.
- Line-item editors expose **Add line item** for custom work and **Price book** for reusable defaults. The Price book
  is a right-side browser that supports multi-add; picked lines remain editable snapshots, and catalog updates are
  always explicit and affect future additions only.
- A dedicated Price Book management screen is separately gated. Saved-item images remain deferred.
- The Quote right rail composes reusable Quote summary, Discount, Deposit, and Tax blocks. Empty financial blocks
  show explicit Add actions; configured blocks show their value and Edit; dialogs own Cancel/Save. Existing Notes
  and Attachments are reused unchanged.
- Quote summary shows customer totals and, only with `quotes.view_cost`, Cost, Estimated profit, and Margin.
- One Quote-level discount has an editable customer-facing name plus fixed/percentage value. Following Jobber, it
  reduces non-taxable subtotal first, then taxable subtotal, before tax is calculated.
- Tax is one named exclusive rate or No tax. Quote override wins over Property then Business defaults; the frozen
  Quote version never follows later default changes. Saved tax-management UI remains separately gated.
- Optional add-ons are the only customer choice on a quote. Good/better/best packages were removed on
  2026-08-21 at Jafar's call: a quote is just a quote and its lines. Alternatives are separate versions.
- The first proposal sections are Introduction, Client message, Contract disclaimer, and customer-visible
  attachments/images. Optional sections use the reusable `AddSectionControl` and stay absent until added,
  following Jobber's composer; Invoices and later document builders reuse the same control. Warranty and
  extra terms stay inside Contract disclaimer for now.
- Reusable Quote templates follow the finished proposal model in a later approved part.
- Material changes after approval invalidate the prior signature and create a new customer-facing version.
- Part 4 builds the immutable freeze/clone foundation; Part 5A exposes publication as the first staff action that
  freezes a version.
- Part 5 sends no email. Communications owns delivery, so the publish action is named `Mark as awaiting response`
  until 5B gives it a customer link to hand over. Jafar's call, 2026-08-21.
- Approval stops follow-ups but does not silently create a Job.
- Converted is terminal, even if the downstream Job is later removed.
- Quotes owns deposit requirements and payment schedules. Payments later owns online card/bank charging,
  processor state, settlement, refunds, and invoice allocation mechanics.
- A required deposit gates readiness to begin work. Percentage deposits recalculate from the customer's
  selected add-ons. Partial online deposit payments are not introduced by this campaign.
- Deposit editing first chooses Deposit only or Payment schedule. Deposit-only and installments support fixed or
  percentage values. No organization-wide deposit preset ships; a later Quote template may carry one.
- Customer-facing Quote access ships with Quotes rather than waiting for a generic portal campaign.
- Staff can see the customer's document through **Preview as client**, and it is the same renderer as the real
  link with the decision buttons inert - never a second copy that can drift. It belongs to 5B because Part 4's
  Client view switches (quantities, unit prices, line totals, totals) currently have no way to be checked.
  Jafar asked for this on 2026-08-21 after noticing the header menu had no such option.
- The customer's own rail carries two buttons, Approve and Request changes, following Jobber. Declining stays
  a staff-recorded outcome: a Decline button hands an unsure client a one-click way to end the job instead of
  asking a question. Jafar's call, 2026-08-21.
- Link expiry is enforced and gets its own honest page, but nothing in the app sets a date yet. A customer-facing
  valid-until date and an extend flow belong with the send work, because extending is customer-visible and
  publishes a new version. Jafar's call, 2026-08-21.
- Signing is offered, never demanded, following Jobber's own default; an organization-wide requirement is a
  setting and waits for Settings. The staff pad is an in-person approval, not a separate act. Jafar's call,
  2026-08-21 - the permanent form lives in `docs/quote-behavior-contract.md`.
- Jafar approved the useful Quote-action scope on 2026-08-21. Part 5B owns Preview as client and print/save
  PDF through the shared customer renderer; Part 5C owns customer and in-person signatures; Part 5D owns
  create-similar, archive/restore, safe draft deletion, and the final status/permission-aware menu. Send as
  Email waits for Communications, and Convert to Job waits for Jobs; neither ships as a simulated success.

## Cross-campaign dependencies

- `sales-pipeline` remains paused until Part 5 establishes real Quote approval truth, then resumes as Part 7.
- Communications owns transport, delivery/retry, reply routing, and automated follow-ups; Quotes owns the
  document recipients, versions, secure access, and business events.
- Payments owns provider processing. Jobs owns the destination Job and visits; Quotes owns conversion
  eligibility and terminal identity.
- Contractor Settings is not part of the current Quotes execution path. Do not add dead Price Book or Tax settings
  links; integrate saved tax/default management only after that separately approved surface exists.

## Main risks

- Money rounding, discount/tax ordering, optional selections, and percentage deposits can diverge unless
  one database-owned calculation contract is used everywhere.
- Concurrent editing, sending, approving, or converting can produce stale approvals or duplicate work
  without version checks, locking, and idempotency keys.
- Public links and quote PDFs can leak cross-tenant pricing or private notes unless recipient/version scope
  is enforced independently of UI visibility.
- Premature email, payment, or Job placeholders would create false completion and unsafe ownership seams.

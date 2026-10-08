# Boulevard P4 — plan review and proposed build order

**Status:** Proposal for Jafar's review, 2026-10-08. This is a build sequence, not permission to build or a claim that the first clinic is ready. The agreed behavior remains in the [product plan](../boulevard-product-behavior-contract.md), the [P3 release boundary](boulevard-p3-release-proposal-2026-10-08.md), and the [P3A performance design](boulevard-p3a-performance-design-2026-10-08.md).

## Consistency review

The approved first release has one connected path: a business is provisioned for the Medspa experience; staff set services, availability and permissions; a client books under the clinic's rules; the treated person completes intake and consent; a clinician clears and charts; checkout applies deposits and prepaid benefits; staff can reconcile money, outstanding work and access history. One-time packages and service vouchers are core. The first clinic's actual services and old obligations decide which conditional capabilities must also be ready. The release boundary does not imply that all Boulevard inventory features are built.

The plan keeps three different questions separate: **what the product should do**, **what has been built and verified**, and **whether a particular clinic can safely switch**. The P3A numbers are proposed test data and speed targets; they do not establish capacity. Public sources support the described vendor patterns but do not establish our Stripe permissions, protected-information agreements, state-specific clinical rules or source-vendor import mappings. Those remain named gates rather than hidden assumptions.

The following rules need care in each build part: a 30-minute slot hold must expire after abandonment; staff booking overrides cannot grant treatment clearance; the payer and treated person may differ; a paid package benefit is used once; clinical photos and messages stay behind the right access boundary; a failed payment or notice leaves visible work; and a historical imported file never becomes current consent or clearance. A conditional feature enters the first clinic's release only after its whole journey is verified.

## Proposed build order

Each row should become one or more focused parts with a working screen, server path, data rules and a visible check. The project should split a row further if its implementation cannot be reviewed in one focused session. Building can use synthetic clinic data while provider agreements and the first clinic's source samples are pending.

| Order | Working result | Depends on and proof |
| --- | --- | --- |
| 1. Industry entry and setup | A Medspa organization gets the right package, menus, permissions and pinned Setup program. | Existing organization/package/Setup foundations; test two businesses on different published program versions and denied actions. |
| 2. Staff appointment foundation | Staff create services, shifts and room rules, then book, move and cancel a conflict-safe appointment. | Order 1; two staff racing for one slot cannot both take it. Staff can see unresolved prerequisites. |
| 3. Client booking and identity | A client signs in with a code and birth-date check, selects an eligible service and time, and manages a booking within policy. | Orders 1–2; abandoned holds expire, age/prerequisite rules apply and no other person's data appears. Add card consent/deposit in the same coherent booking journey before a clinic that requires it can go live. |
| 4. Clinical visit | The treated person completes versioned intake and consent; an authorized clinician records clearance, chart and named review. | Orders 2–3; missing clearance blocks treatment start, signed versions remain intact, old photos cannot masquerade as new ones, and unauthorized URL/file access fails. |
| 5. Money at the appointment | Staff settle an order with supported tenders, deposit, receipt, refund and visible failed-payment recovery. | Orders 2–4 and clinic-owned Stripe permissions; no double charge, deposit application or untraceable correction. |
| 6. One-time paid benefits | Staff sell, use, expire where permitted and refund packages and service vouchers; checkout shows remaining value. | Order 5; purchase, partial use and refund reconcile without counting redemption as new money. |
| 7. Notices and client follow-up | Neutral booking/receipt messages, delivery status, staffed replies and self-service changes run from appointment events. | Orders 3, 5–6; moved bookings retire old reminders, opt-out is honored and no clinical detail leaks into messages. |
| 8. Daily control | Staff see permissioned daily sales, deposits, benefits, refunds, payout differences, overdue review and clinical access audit. | Orders 4–7; totals trace to source movements and restricted staff cannot export hidden data. |
| 9. Reviewed migration | An existing clinic can review client matches, future bookings, old paid value and historical files before switching. | Orders 2–8 and source-specific samples; unresolved records remain in review, totals match, files are labelled historical. |
| 10. Clinic-dependent journeys | Build and verify only the selected clinic's required guardian/group, recurring membership, retail, stock, commission, text reminder or connection behavior. | Core foundations plus the clinic profile; an allowed outside stock process is documented and never shown as product stock tracking. |
| 11. Connected release proof | Rehearse booking through closeout, failed dependencies, staff permissions, migration and the whole-app performance audit on the approved deployment. | Orders 1–10 as applicable; the first clinic passes the [P3 eligibility checklist](boulevard-p3-release-proposal-2026-10-08.md#first-clinic-eligibility-and-journey-proof). |

Order 3 and order 5 deliberately share the card/deposit boundary: the booking slice must prove the card flow before a card-required clinic is accepted, while order 5 finishes appointment money and reconciliation. Workload and speed evidence from [P3A](boulevard-p3a-performance-design-2026-10-08.md) belongs to each material slice and is repeated at the whole-app release audit where shared resources interact.

## Decisions for Jafar

1. Approve or change the **provisional performance test envelope and screen targets** in P3A. The first clinic's real size and busy periods replace the assumptions before its go-live test; no registered-user capacity promise follows.
2. Approve or change the **build order** above. Conditional features are selected from the first clinic's actual needs, then inserted before its connected release proof.
3. Confirm that the current source/provider/state checks remain **launch gates**, so core building may start with synthetic data while the clinic-specific agreements, source files and policies are still being verified.

After these decisions, record the approved build parts in the campaign plan or a new build campaign. A build start and any production infrastructure migration need their own approval under the project rules.

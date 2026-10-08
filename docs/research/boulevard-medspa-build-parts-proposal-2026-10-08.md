# Medspa first release — proposed build parts

**Status:** Proposed for Jafar's review, 2026-10-08. The [Medspa behavior](../boulevard-product-behavior-contract.md), [release boundary](boulevard-p3-release-proposal-2026-10-08.md), [performance test contract](boulevard-p3a-performance-design-2026-10-08.md), and [build order](boulevard-p4-review-proposal-2026-10-08.md) are approved. These parts organize delivery; they do not authorize implementation or establish clinic readiness.

**Goal:** A suitable single-location clinic can take a person from booking through verified intake, clinical care, payment, follow-up and daily reconciliation in one Medspa experience, with its actual old obligations and clinic-specific needs checked before switching.

Every part includes the usable screen, `/api/*` path, data/access rules and meaningful checks needed for its result. Before a scale-sensitive part, apply the approved P3A workload and performance design gate; after it works, measure the affected path. A part closes only after its behavior and access checks pass on `main`. Reuse existing contractor foundations only after checking their fit. The listed order follows the approved P4 sequence; a dependency does not grant the earlier part permission to assume provider, legal or source-data readiness.

| Part | What Jafar can try and observe | Waits for |
| --- | --- | --- |
| **1A Industry and access** | Provision a test Medspa business; its purchased features and staff permissions govern menus, API actions and records. A contractor business retains its own experience. | Existing organization/package/permission foundations. |
| **1B Published Setup versions** | Publish a Medspa Setup program and start two clinics on different versions; republishing does not rewrite either clinic's started tasks. | 1A and existing Setup publishing. |
| **1C Assisted Medspa entry** | Jafar reviews a Medspa application, chooses business type and package, then invites its owner into the pinned Setup journey; an unresolved mixed-service application waits for review. | 1A–1B and existing assisted application. |
| **2A Services and requirements** | Staff define a service, time segments, price, provider options, minimum age and prior-visit requirements; an existing booking keeps its agreed price and length. | 1A. |
| **2B Staff and room time** | Staff publish shifts, blocks and room/equipment rules; a bounded day/week calendar shows permitted appointments and availability. | 2A. |
| **2C Staff booking and contention** | Staff book a person and see conflicts or unmet requirements; two simultaneous requests for the last staff/room slot yield one booking. An override has a saved reason. | 2A–2B. |
| **2D Change and cancel** | Staff move, cancel, restore and prebook visits under policy; future visits prevent unsafe staff deactivation and a cancelled prerequisite flags dependent treatment. | 2C. |
| **3A Client code and birth date** | A client signs in by one-time code, confirms birth date before private Medspa data, and sees only their clinic profile; ambiguous adult contact details go to staff review. | 1A and client identity review. |
| **3B Online eligibility and slots** | A client sees eligible services and a bounded set of times; age and prerequisite rules block unsuitable treatment and explain the required first visit. | 2C, 3A. |
| **3C Hold and confirm booking** | A selected slot is held for 30 minutes, expires after abandonment, and becomes one confirmed visit despite simultaneous attempts or repeated submit. | 3B. |
| **3D Card and booking deposit** | With verified clinic-owned Stripe permissions, the client consents to a saved card and pays a disclosed deposit when required; a failed or uncertain payment leaves visible work. | 3C and provider/key checks. This builds the narrow booking-payment foundation later completed in 5A–5C. |
| **3E Client booking changes** | The client sees their own visit and can move or cancel it within policy; a deposit follows the changed visit exactly once. | 3D and 2D. |
| **4A Clinical access and files** | Authorized staff open one person's clinical area and protected files; another role, clinic or revoked session cannot reach them by URL or download. Access is recorded. | 3A and staff permissions. |
| **4B Versioned intake and consent** | The treated person completes intake and signs the exact consent version; a later template edit leaves the signed version intact. Historical attachments remain labelled historical. | 4A and booking identity. |
| **4C Treatment clearance** | A permitted clinician records the prerequisite result and clearance; missing or expired clearance blocks treatment start even when staff overrode a booking warning. | 2D, 4B. |
| **4D Chart and photos** | A clinician charts the visit and attaches protected photos; corrections preserve the signed history and an old photo cannot appear as a new one. | 4A–4C. |
| **4E Named review** | A named reviewer signs off the chart or sees overdue work; checkout cannot imply clinical review. | 4D. |
| **5A Appointment order** | Staff open an order for the visit, apply a deposit once, and see an unresolved state for failed or pending payment. | 3D and 4C. |
| **5B Settlement and receipt** | Staff settle supported tenders and issue a receipt; repeat submits or webhook replay do not collect twice, and unsupported tender choices are absent. | 5A and tested Stripe permissions. |
| **5C Refund and correction** | Staff refund a named original line, see the processor outcome, and retain a trace of corrections; a delayed failure remains in the work queue. | 5B. |
| **6A Sell a one-time package** | Staff sell a versioned package and the client sees remaining service units and paid value; purchase is counted once. | 5B. |
| **6B Use and return package value** | Checkout uses one eligible package benefit once; partial use, expiry where permitted, cancellation and refund explain the remaining balance. | 6A, 5C. |
| **6C Service vouchers** | Staff sell, assign, redeem and refund a service voucher, with a separate history from cash, credit and package units. | 6B. |
| **7A Appointment and receipt notices** | Neutral messages follow booking, move, cancellation and receipt events; old reminders retire, opt-out works, and a failed delivery stays visible. | 3D, 5B and existing communications delivery. |
| **7B Staff replies and client follow-up** | Staff see and answer client replies with the correct access; ordinary messages expose no chart detail. | 7A and existing inbox suitability check. |
| **8A Daily money and benefits** | Permitted staff trace daily sales, new money, deposit, refund and redeemed value to source movements without counting a redemption as new cash. | 5C, 6C. |
| **8B Payout and exception work** | Finance staff trace processor fees and payout differences and mark bank arrival separately; pending payments and unexplained differences keep an owner and history. | 8A and verified Stripe payout access. |
| **8C Clinical review and access audit** | Leadership sees overdue named reviews and access/download history; restricted staff cannot view or export hidden clinical or finance fields. | 4E, 8A. |
| **9A Client import review** | An authorized reviewer matches duplicate people from a real source sample; unresolved rows cannot become active profiles. | 3A and a source-specific sample. |
| **9B Future-visit import review** | Staff compare future appointments against the live calendar and approve only conflict-free, attributed visits. | 2D, 9A and source-specific appointments. |
| **9C Old paid value review** | Staff reconcile each supported old package/voucher balance to source totals before activation; an unsupported obligation keeps the clinic from switching that journey. | 6C, 9A and source totals. |
| **9D Historical file attachments** | Authorized staff attach attributed old files, review the import, and see a permanent historical label; no import creates consent, clearance or chart sign-off. | 4D, 9A and reviewable source files. |
| **10 Clinic-dependent parts** | After choosing a real clinic, add only the journeys it needs: representative/minor access, group visits, recurring memberships, retail or full stock trace, commission, registered text reminders or a specific connection. Each gets its own small parts and complete done-check before that clinic uses it. | The clinic profile and applicable core parts. Exact parts remain unassigned until then. |
| **11A Connected rehearsal** | Staff and a test client complete booking → intake → clearance/chart → checkout/benefit → receipt/report, including payment, message, permission and import failures. | Core parts and required 10 parts. |
| **11B Release evidence** | Run the first-clinic eligibility review and whole-app performance audit against its real workload on the approved deployment; record passing results and remaining limits before a go-live promise. | 11A, clinic/provider/state checks and separately approved infrastructure migration. |

## Decisions needed before this becomes a roadmap

1. Confirm whether these parts are a useful size and whether the sequence is right. A part can be split further when its actual build proves too large for one focused session.
2. Approve a separate build start before implementation. The planning approval on 2026-10-08 did not include that permission.

The first clinic is deliberately unnamed. Its state, services, age groups, old balances, source files and stock practice choose Part 10's scope. Synthetic clinic data can support core development; it does not pass the first-clinic eligibility check.

# Boulevard P3A — first-release performance design

**Status:** Planning test contract, 2026-10-08. These are targets and assumed test loads, not measured results or a promise that the current app supports a clinic. The [P3 release boundary](boulevard-p3-release-proposal-2026-10-08.md) sets the first clinic's actual eligibility; its real profile replaces these assumptions before a go-live claim. No infrastructure change is approved here.

## Workload to design and test

The first release serves one location per clinic. Test both a representative clinic and a larger clinic so a quiet demo cannot hide growing work. These values are **P3A test assumptions**, not facts about a selected clinic or market capacity.

| Dimension | Representative test | Larger test and burst |
| --- | --- | --- |
| Clinic data | 20 staff, 10 rooms, 150 services, 10,000 people, 50,000 past appointments, 2,000 future appointments, 100,000 payment/benefit movements | 60 staff, 25 rooms, 300 services, 50,000 people, 250,000 past appointments, 10,000 future appointments, 500,000 movements |
| Clinical data | 50,000 chart records; 10 file references per chart in the heavier sample; files held in protected object storage | 250,000 charts with the same file mix; measure real file-size distribution separately |
| Active use | 10 staff sessions, 20 public booking sessions, 2 completed bookings per minute | 30 staff sessions and 60 public sessions for 10 minutes; 6 booking attempts per minute, including competing requests for the same slot |
| Background work | 200 appointment/receipt notices per day; one reviewed import of 5,000 people | 1,000 notices per day; import 25,000 people while ordinary booking and checkout continue |

The staff mix must include an owner, front desk, restricted clinician, and finance user. Test a second clinic with data at least as large as the representative one to expose accidental work across tenants. Use realistic distribution: one busy clinician and room, popular services, duplicate clients, outstanding package/voucher balances, failed payments, and old chart attachments. Measure cold and warm reads separately. A clinic whose actual data, concurrency, file sizes, or peak booking traffic exceeds the larger test needs an expanded test before acceptance; the larger test alone still proves no production capacity.

## Smallest sound shape for each growing path

| Journey and growth term | Design before code | Evidence after its coherent build slice |
| --- | --- | --- |
| Public service and slot search: services × staff × rooms × requested days; simultaneous claims on one slot | Search a bounded date window (initially 14 days) and a chosen service, return a small page of available starts, and ask for another window explicitly. Check staff, room, prerequisite and hold rules at the authoritative booking write. A displayed slot is provisional. | Query plans and scanned/returned row counts at both data sizes; API latency and payload; competing attempts for one slot yield one booking; expiry and cancellation release capacity. |
| Staff calendar: appointments and resources in the visible window | Load one location and a visible day/week plus a small margin; fetch compact appointment summaries only. Open a booking for clinical/money detail. Filter by permitted staff and room before return; never download a year's appointments to render a week. | Query count, plan, returned bytes and DOM item count for a busy week; scroll/change-week interaction timing on a slowed phone; restricted-role results and a second clinic remain isolated. |
| Person search and chart: people, historical visits and protected files | Search within the clinic and authorized scope with a result cap; page history in stable order. Fetch the selected chart and its file metadata on demand; load images as sized derivatives only when viewed. A URL or cached browser result never grants chart/file access after permission or session revocation. | Search and history plans at both sizes; returned bytes and chart open timing; file count/bytes; denied URL/download tests and revocation test. |
| Checkout and prepaid value: order lines, benefit movements, external payment latency and retries | Read only the active order and applicable benefits. Keep the money and benefit write atomic and idempotent; show a pending state until the authoritative outcome. Do not hold a database lock while waiting for Stripe. Retrieve processor status when needed and reconcile delayed webhooks. | Payment/order/benefit query counts and timings; repeat/parallel submit and webhook replay produce one movement; failed or slow provider leaves visible unresolved work; p95 user wait reported with provider time separated. |
| Reports and audit: retained money, benefit and access events | Date-bound and permission-bound reads with pages and totals from the same definitions as checkout. Start with live bounded queries; add a maintained summary only if representative plans miss the budget and its freshness/rebuild behavior is defined. Audit and exports page or stream rather than building an unbounded in-memory result. | Plans, scanned rows, result bytes and latency for a day and month at both sizes; reconciliation to source movements; export memory/size/time and denied-field tests. |
| Notices and migration: recipient/event fan-out and large source files | Reuse the project's existing worker/import patterns where suitable. Process bounded batches with idempotent event keys, retry limits, visible failures and per-clinic fairness. Import review and commit must not block ordinary clinic traffic or make unapproved data active. | Queue depth, age, throughput, retries and duplicates during the larger import/burst; booking/checkout latency while it runs; interrupted import resumes without double booking or balance creation. |

The route from a browser action to completion includes SvelteKit rendering, `/api/*` authorization, Supabase query work, Stripe or messaging where relevant, R2 for protected files, and background workers. Each build part should record round trips, rows scanned and returned, payload, browser work and the finite resource it can saturate. Select indexes from actual filter/order/permission predicates and inspect plans before adding them. [Supabase's query guidance](https://supabase.com/docs/guides/database/query-optimization) supports measuring plans and balancing faster reads against write cost; its [RLS guidance](https://supabase.com/docs/guides/troubleshooting/rls-performance-and-best-practices-Z5Jjwv) specifically calls for testing policy cost. No new cache, read model, partition, service, or Realtime channel is justified by this planning evidence alone.

## Route and browser budgets

The following are **acceptance targets for a production build in a production-like environment**, measured at the representative workload and repeated at the larger workload. API targets are p95 over repeated actions and exclude only time spent on a named external provider; the full user wait is also reported. A missed target triggers diagnosis or an agreed budget revision with evidence, never a silent pass.

| Surface or action | Planned target | What the measurement includes |
| --- | --- | --- |
| Public entry, code sign-in, first booking view | [Core Web Vitals](https://web.dev/articles/vitals) “good” thresholds on phone: LCP ≤ 2.5 s, INP ≤ 200 ms, CLS ≤ 0.1 at p75 | First visit and return visit; rendered HTML, route JavaScript/CSS, fonts, images, requests, CPU and network. |
| Slot search and booking confirmation | Slot results ≤ 1 s p95 after the request; confirmation ≤ 1 s p95 after the authoritative local write, with Stripe/provider wait shown separately | A 14-day search, a popular service, last-slot contention, retry and failure. |
| Staff calendar and person search | Visible week ≤ 1 s p95; capped person search ≤ 0.5 s p95 | Restricted and owner views, large clinic, normal/empty search, compact payload and visible item count. |
| Chart open and sign-off | Selected chart's usable text/metadata ≤ 1 s p95; signing ≤ 1 s p95 after local write | File thumbnails/content separately; denied access and revision conflict remain correct. |
| Checkout and daily report | Local order/benefit action ≤ 1 s p95; one-day report ≤ 2 s p95 | Reconciliation, large clinic, refund and benefit history; provider time and export completion reported separately. |

These API times are our proposed budgets, not Boulevard or Google standards. Google defines the Core Web Vitals thresholds at the 75th percentile; lab tools without user interaction cannot measure real INP. Use scripted representative interactions and later real-user measurements for INP. Before each slice is accepted, record compressed initial JavaScript/CSS, fonts/images, request count, API response bytes, server and database time, DOM size and interaction trace. Compare route bytes with the contractor baseline, and set an explicit route byte cap once the first medspa production build exists; an arbitrary cap today could hide the true shared-shell cost. Unavailable industry/capability code and assets must contribute **zero route-specific bytes** to that clinic's initial journey. Reserve space for late panels; do not use an optimistic success state for contested booking, payment or clinical approval.

## Delivery, correctness and failure rules

- Server-render the public entry, sign-in and first usable workspace content where it removes a first-load wait. Load calendar/chart/payment tools only on their route or when opened. [SvelteKit page options](https://svelte.dev/docs/kit/page-options) allow route-level rendering choices; the implementation must measure whether a server render duplicates a browser fetch.
- Tenant and role checks apply to every search, page, report, file and live event. Browser cache keys include clinic and authorization context; revoke or invalidate sensitive results after permission/session changes. An index or faster read cannot weaken isolation.
- Availability, package value and checkout are authoritative at the write. Under contention, the loser gets a clear retry or alternate-slot result. A slow provider cannot hold a booking or money transaction open indefinitely. Retries use one idempotent intent and expose unresolved outcomes.
- Keep worker concurrency bounded. When the provider or database slows, queue work with visible age/failures rather than spawning unlimited requests. The first release does not need Realtime unless a tested staff journey requires it; if introduced, measure connection count, filtered event rate, fan-out and cleanup.
- Measure against the intended Docker app/worker and official self-hosted Supabase topology before release only after Jafar approves that separate infrastructure migration. Until then, a managed-remote test must name its regions, network, hardware and difference from the intended deployment. R2 and Stripe remain external boundaries. No VPS size or concurrency promise follows from this document.

## Design verdict and release evidence

**Growth path:** bounded searches and visible windows; retained clinical, appointment and money history; bursts around popular slots; provider and worker contention.

**Chosen shape:** tenant/role-scoped bounded reads, demand-loaded detail and media, authoritative short writes, idempotent payment/notice/import work, and existing worker primitives where fit is proven.

**Complexity cost:** no speculative cache, partition, replica, new queue or maintained summary. Query-specific indexes and worker limits are decided in the corresponding build slice from measured plans and the actual data model.

**Rejected for this workload:** loading entire calendars/charts into the browser, precomputing all reports, and adding a general Realtime layer before a journey proves it needs one.

**Verification:** each table row above supplies a measurable check; P4 build parts must attach the corresponding proof. The whole-application release audit must also check the representative booking-to-closeout journey, all shared resources and the approved deployment path. An unmeasured layer is recorded with reason, impact and owner; it is not counted as passing.

**Open decisions:** The selected clinic's staff, service, booking, history, file and peak-traffic profile; exact upload limits; and approved deployment topology are required before a clinic-specific or production capacity statement. P4 may approve build sequencing with this test envelope, but the first clinic's profile must be checked against it before go-live.

**Overall:** Ready as a conditional design gate for build planning. Speed and capacity remain unverified until implementation is measured at a named workload and environment.

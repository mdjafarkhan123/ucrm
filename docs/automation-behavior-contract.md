# Automation behavior and architecture contract

Status: Approved by Jafar, 2026-08-30  
Owner: Contractor Settings campaign, Part 6

## Purpose and authority

This contract turns the approved Automation direction in `docs/contractor-settings-blueprint.md` Part 6 into
one executable product and architecture contract. Approval of this document does not authorize migrations,
permissions, routes, workers, package publication, or UI implementation. Each campaign part retains its own
approval and verification gate.

The chosen production pattern is a durable, versioned workflow interpreted by a bounded worker. Domain changes
and their events commit together; Automation consumes those events, advances one persisted enrollment at a time,
and records each external effect behind an idempotency key. This is the smallest proven shape that survives
restarts, duplicates, delays, and concurrent workers without making Automation the owner of Quote, payment,
consent, or delivery truth.

Jobber establishes the contractor mental model: recommended presets plus a progressively disclosed
When -> optional If -> ordered Then/Wait -> Stop when builder. UCRM keeps the approved differences: saving never
activates, activation has an impact review, presets are editable recipes, live safety always uses current truth,
and customer replies pause future customer-facing steps.

The live Jobber tour normally required by the project design process was explicitly waived by Jafar on
2026-08-30. Existing Jobber reference material and the already-approved UCRM blueprint remain the comparison
sources; no new Jobber behavior is inferred here.

Implementation follows established production patterns and extends proven UCRM platform primitives before
adding machinery. A new abstraction, table, service, dependency, or protocol must solve a named requirement that
the existing versioned-access, Postgres transaction, worker, outbox, audit, or query patterns cannot safely meet.
"Future proof" means stable contracts, explicit ownership, safe extension seams, and measured thresholds—not
speculative generality.

## Language and ownership

| Term | Meaning and owner |
| --- | --- |
| Recipe | Organization-owned Automation identity, name, status, preset lineage, and current draft/active version pointers. Automation owns it. |
| Recipe version | Immutable activated definition and canonical hash. An editable draft is not an activated version. Automation owns it. |
| Event | Durable statement that a domain fact occurred. The emitting domain owns its meaning and transaction; Automation owns consumption state. |
| Enrollment | One subject executing one recipe version because of one qualifying event or explicit manual command. Automation owns it. |
| Work item | One due transition for an enrollment: evaluate, wait completion, or action attempt. Automation owns scheduling and claims. |
| Action effect | The logical side effect requested by one action step. The receiving domain owns the resulting Task, notification, or message. |
| Attempt | One worker try against one work item or action effect. Automation owns operational history. |
| Stop condition | Current domain truth that prevents later steps. The source domain owns the fact; Automation owns the stop decision. |
| Needs attention | A recoverable enrollment or recipe problem requiring an authorized person. It is not a generic error log. |
| Preset | A platform-authored starting definition copied into an organization-owned recipe. Later platform edits never overwrite the copy. |

Automation never owns Quote state, customer consent/preferences, suppressions, channel readiness, provider
delivery, payment truth, or Task truth. It asks the owning module immediately before an effect. The receiving
module returns an accepted, deferred, rejected, or already-completed result without exposing provider secrets.

## Deep module seams

Automation exposes four small server interfaces. Routes, workers, record pages, and tests use these interfaces;
they do not assemble workflow state directly.

1. **Recipe authoring:** create/update draft, validate draft, activate, pause, resume, and archive. It owns
   optimistic conflict checks, definition validation, immutable version creation, impact calculation, and audit.
2. **Event intake:** accept one typed domain event with its source id. It owns deduplication, activation cutoffs,
   recipe matching, enrollment/re-entry decisions, and initial work creation.
3. **Execution:** claim a bounded batch, advance one enrollment, and settle a result. It owns leases, ordering,
   retries, stop/safety checks, effect idempotency, and attention state.
4. **Enrollment control:** preview manual enrollment; enroll, pause, resume, skip next, or stop one enrollment. It
   owns authorization, stale-command rejection, eligibility preview, audit, and cache invalidation.

Domain adapters are real only when a domain has an approved trigger, condition, stop check, or action. The first
adapters are Quotes and Communications. Internal notifications and Tasks are added only when their owning modules
offer a durable command; placeholder adapters are not created.

## Recipe definition and lifecycle

One versioned, typed definition powers presets and build-from-scratch recipes:

```text
When: one typed trigger
If: zero to six conditions, all true in v1
Then: ordered action and Wait steps
Stop when: one or more domain-owned stop conditions
```

- A definition stores a schema version plus typed trigger, conditions, steps, and stop conditions. The server
  validates it with the same catalog used by the builder, stores its canonical JSON and hash, and rejects unknown
  types or fields. The browser never submits executable code, SQL, URLs, provider credentials, or arbitrary
  expressions.
- V1 has a linear ordered sequence. Nested branches, loops, parallel paths, inbound webhooks, arbitrary HTTP,
  scripts, and a node canvas are later separately approved capabilities.
- Preset selection copies the current platform preset into a new organization draft and records lineage for
  explanation only. The organization copy is independent. A newer preset may be previewed and adopted into a new
  draft; it never rewrites an organization recipe or live enrollment.
- Recipe states are Draft, Active, Paused, and Archived. Save updates only a draft. Activate freezes a new version
  after review and starts future-event eligibility. Editing an Active or Paused recipe creates or updates a draft
  based on its active version. Activating that draft changes new enrollments only.
- Each enrollment stays pinned to the version under which it started. Current consent, preference, suppression,
  recipient, sender, entitlement, organization state, delivery, reply, payment, lifecycle, and abuse facts are
  never pinned.
- Pausing stops new enrollment and holds unclaimed future work. A worker that already owns a lease finishes only a
  non-customer internal transition; every customer effect rechecks pause before acceptance. Resume continues
  still-eligible enrollments without enrolling events that happened while paused.
- Archiving is explicit and stops every non-terminal enrollment after an impact preview. Archived recipes are
  read-only and retain versions/history subject to retention. Restore creates a new draft; it does not reactivate
  an old version.
- Draft updates use a revision supplied by the caller. A stale save returns the newer editor and time and offers
  review or discard, never blind overwrite.

## Catalogs and extension rules

Every catalog entry declares its stable key, owning domain, configuration schema, compatible subject, preview
copy, permission/entitlement needs, live safety checks, and terminal/retry outcomes. Adding a key is a behavior
change owned jointly by Automation and the source/receiving domain; generic database rows do not make a new action
safe.

### Quote v1 catalog

The catalog is designed now; 6D enables only the dependency-ready subset.

| Kind | Entries | First enabled subset |
| --- | --- | --- |
| Trigger | Customer delivery succeeded; customer viewed; customer requested changes; customer approved; customer declined | Customer delivery succeeded for an emailed published Quote |
| Condition | Current Quote status; total comparison; assigned owner; recipient still attached; follow-up preference; delivery channel | Current status is Awaiting response and recipient remains eligible |
| Wait | Relative days/hours using organization timezone and an explicit local send window | Day delay after successful delivery |
| Customer action | Send operational email; later send operational SMS when SMS is ready | Email through Communications |
| Internal action | Notify an eligible staff member; create Task | Deferred until each owning command exists |
| Quote action | Update an individually approved Quote status | Not enabled in 6D |
| Stop when | Approved, declined, changes requested, archived, converted, expired, recipient/preferences invalid, customer reply | All applicable non-response/safety outcomes |

The recommended Quote follow-up preset starts from successful delivery, proposes two editable reminders at three
and seven days, and stops as soon as the Quote no longer awaits a response. The exact delay defaults remain part
of Jafar's approval of this contract; organizations may change them within effective platform/package limits.

Website Chat, invoice, payment, Job/review, Scheduling, lead, missed-call, booking, on-my-way, and receipt entries
remain absent from contractor catalogs until their owning contracts and channels are dependency-ready.

## Events and transaction ownership

- A domain command commits its durable fact and one versioned domain event in the same Postgres transaction. A
  callback handler does the same when an external provider establishes delivery truth. Automation never treats a
  browser request, publication alone, an open pixel, or a best-effort in-memory callback as the trigger.
- Each event has a database sequence, UUID, organization, stable type, payload schema version, subject type/id,
  occurred time, source module, source event id, and the minimum immutable context needed to resolve current truth.
  A unique source-module/source-event-id/type constraint makes replay harmless.
- An event payload contains identifiers and trigger evidence, not a reusable authorization decision or a full
  customer/message snapshot. Intake resolves the subject inside the event's organization.
- Activation records the current event sequence as its cutoff. Automatic enrollment accepts only later events.
  Event timestamps are not used for this decision because clocks and delayed callbacks can arrive out of order.
- Intake is resumable. A claimed event is complete only after every matching recipe has either created/deduplicated
  an enrollment or recorded a reason it did not. A crash replays the same event safely.
- For Quote follow-up, Communications owns provider status. Its successful-delivery transaction emits the typed
  event only for a delivery intent linked to the current published Quote version and recipient. Duplicate and
  out-of-order provider callbacks cannot create duplicate enrollment.

## Enrollment, re-entry, and overlap

- Automatic enrollment uniqueness is recipe version + trigger event + subject. Manual enrollment uniqueness is
  recipe version + subject + explicit command id. Both are organization scoped.
- A recipe declares one of: once per subject, once per qualifying version, or on each qualifying event with a
  catalog-owned re-entry key. Quote follow-up uses once per Quote version and recipient delivery.
- Manual enrollment is available only for one eligible existing record at a time. Preview shows recipe version,
  recipient/channel, first due time, stop/safety results, overlap, and expected message count. Confirm uses a fresh
  preview revision and an idempotency key. Bulk or silent retroactive enrollment is unavailable.
- Different recipes may enroll the same record concurrently. Activation and manual preview identify same-subject,
  same-category overlap. Exact logical effects dedupe permanently. Customer messages for the same organization,
  recipient, work record, and operational category are serialized through a platform-controlled cooldown
  (proposed default 15 minutes); the later effect rechecks current truth and either waits or cancels as redundant.
- A customer reply pauses remaining customer-facing steps for relevant enrollments and creates one actionable
  owner/admin notification. Internal steps may continue only when their catalog says a reply does not invalidate
  them. Authorized staff explicitly Resume, Skip next step, or Stop.

## Scheduling, claims, effects, and recovery

Postgres is the durable source of event, enrollment, due-work, effect, and attempt truth. Redis may later wake or
distribute workers, but losing Redis cannot lose or duplicate logical work.

- Completing one step transactionally writes its history, advances the enrollment, and creates at most one next
  due work item. The engine does not pre-expand an entire long sequence.
- Workers claim a bounded batch with one atomic database command using deterministic due-time/id ordering and
  `FOR UPDATE SKIP LOCKED`. A short lease records worker and expiry. Network/provider calls happen after commit.
- Organization-aware ordering prevents one hot tenant from taking the entire batch. The claim command first caps
  work per organization, then fills remaining capacity. Exact batch and fairness values are configuration proven
  by load evidence, not public capacity promises.
- A logical action effect has one stable idempotency key derived from enrollment, version, step, and action
  occurrence. The receiving module accepts that key. A timeout with unknown outcome is reconciled before retry;
  Automation never assumes failure and repeats blindly.
- Immediately before a customer effect, the action adapter rechecks recipe/organization state, current recipient,
  document version/status, reply, consent/preference, suppression, entitlement, channel allowance, sender/domain,
  timing window, cooldown, and provider safety. A permanent mismatch cancels the step with a plain reason. A
  temporary condition defers it until a bounded deadline. A platform/security suspension fails closed.
- Retry policy is catalog-owned. Transient internal/database failures use exponential backoff with jitter. Customer
  effects also respect their usefulness deadline. Permanent validation, opt-out, suppression, stale record, or
  terminal lifecycle results do not retry.
- Expired leases return to claimable state. Attempt count, last safe error code, next retry, and correlation id are
  visible in Needs attention. Error text is sanitized; credentials, headers, message bodies, and customer secrets
  never appear in operational logs.
- A dead-letter state is terminal for automatic retries but recoverable by an authorized command that reruns all
  current checks and creates a new visible attempt under the same logical effect.
- Current managed deployment may invoke the worker module through a secret internal route on a Supabase Cron
  cadence, reusing the existing worker pattern. Production runs the same module in an immutable background-worker
  container using pooled database access. Cron remains a recovery wake-up. Neither deployment changes semantics.

## Entitlement, permissions, and commands

Automation reuses versioned package features/limits and reasoned, effective-dated organization exceptions.

- Feature key: `automations`. The existing unused `automation.workflows` key is legacy: immutable historical
  package versions retain it, it grants no Automation runtime access, and new package drafts cannot assign it.
- Permission keys: `automations.view`, `automations.manage`, `automations.activate`, and
  `automations.control_enrollment`. Owner/admin defaults receive all four; employee defaults receive view only when
  the package includes Automation. Member overrides may narrow access but never bypass package or suspension.
- `view` reads recipes/history allowed by the organization. `manage` creates and edits drafts/presets.
  `activate` performs activate/pause/resume/archive impact commands. `control_enrollment` performs preview/enroll,
  pause/resume/skip/stop on an eligible record.
- Every POST/PATCH route validates with Zod, then re-resolves organization access server-side. State-changing
  commands also enforce expected revision, organization ownership, entitlement, permission, suspension, and an
  idempotency key in the atomic database command.
- Browser payloads expose plain denial reasons, effective values, and safe correction links; they never expose
  internal feature keys, permission keys, service credentials, or cross-tenant existence.
- The Settings destination is hidden without effective feature + view permission and remains hidden from ordinary
  packages until a useful execution slice is ready. A direct route returns a deliberate forbidden/not-included
  response rather than an empty list. Suspended organizations with view permission retain read-only history and see
  the suspension reason; all authoring/activation/effect commands fail closed.

Initial limits are catalog entries, not hard-coded UI constants:

- active recipes;
- conditions per recipe (recommended platform default 6);
- steps per recipe;
- customer messages per enrollment;
- minimum customer-message spacing;
- maximum individual delay (recommended platform default 90 days);
- maximum enrollment duration;
- permitted trigger/action catalog keys; and
- channel allowance, owned and counted by Communications rather than duplicated by Automation.

The current access implementation has explicit versioned limit rows and server-side definitions rather than a
generic limit-catalog table. 6B extends those established seams with explicit Automation keys, validation,
resolution, and labels. It does not introduce a generic entitlement framework merely to avoid listing the known
limits.

An organization may save drafts above its active limits but cannot activate them. A later package downgrade does
not delete recipes or history: new enrollment stops, current customer effects fail closed, and administrators see
which recipes must be reduced or which access must be restored. Legal, consent, suppression, provider safety,
tenant isolation, idempotency, and platform security suspension have no organization override.

Automation authority is distinct from entitlement. Its platform-controlled state is Enabled, Operationally
disabled, or Security suspended, with a safe reason and audit. Disabled and suspended organizations with view
permission retain read-only definitions and history; every authoring, activation, enrollment-control, and effect
command fails closed. Action availability is an explicit allowlist resolved from the package default and a
reasoned/effective-dated organization exception; it never weakens catalog safety checks.

## Query, index, and count contract

Every growing read is tenant-scoped, bounded, and ordered with a unique tie-breaker.

| Read/claim | Predicate and order | Required index shape |
| --- | --- | --- |
| Recipe home | organization + status, updated_at desc, id desc | `(organization_id, status, updated_at desc, id desc)` |
| Active trigger match | organization + trigger key + active | Partial `(organization_id, trigger_key, id)` for active versions |
| Event intake | unprocessed/available sequence, id | Partial `(available_at, sequence, id)` for pending events |
| Due work claim | claimable status + due_at, organization, id | Partial `(due_at, organization_id, id)` for pending/expired-lease work |
| Enrollment by record | organization + subject type/id, updated_at desc, id desc | `(organization_id, subject_type, subject_id, updated_at desc, id desc)` |
| Needs attention | organization + attention state, updated_at desc, id desc | Partial `(organization_id, updated_at desc, id desc)` for attention rows |
| Recipe history | organization + recipe, occurred_at desc, id desc | `(organization_id, recipe_id, occurred_at desc, id desc)` |
| Global cleanup | retention class + terminal time + id | Partial `(retention_class, terminal_at, id)` for deletable rows |

All recipe, enrollment, and history lists use cursor pagination. The cursor includes every sort column and id;
pages never use deep OFFSET. List responses project summaries, not definitions, event payloads, rendered messages,
or attempt stacks. A revealed history tab prefetches on hover and queries only when opened, following the app's
TanStack Query contract.

No maintained UI count ships initially. Organization recipe/attention counts are bounded indexed queries; list
pages may return a capped/exact total only when its plan meets the budget. Global health and retention preview run
bounded aggregate jobs, not counters on a hot write row. A repairable maintained count is added only if 6D/6E
measurement proves the indexed query misses its budget.

Partitioning, a second datastore, a generic event bus, and a separate workflow dependency are rejected for the
initial workload. Time partitioning is reconsidered when an affected history/event table approaches 100 million
rows or measured vacuum/retention behavior requires it.

## Performance design verdict

**Growth path:** domain events -> recipe matches -> enrollments -> due work -> attempts/effects -> history. Work
grows with organizations, active recipes, event bursts, scheduled steps, customer fan-out, retries, and retention.

**Planning workload, not a capacity claim:** 20,000 registered staff across up to 10,000 organizations; 100,000
active recipes; 1,000,000 domain events/day with a 250 events/second five-minute burst; 500,000 due transitions/day
with 100 due/second bursts; a 100,000-item recoverable backlog; and one hot organization producing 10% of a burst.
Interactive lists return at most 50 rows. Exact real usage is unknown and these values are conservative test
assumptions for architecture selection.

**Chosen shape:** indexed Postgres truth, immutable definitions, transactional domain events, incremental work
rows, atomic leased claims, bounded/fair workers, idempotent receiving commands, cursor history, and no correctness
dependency on Redis.

**Complexity cost:** the minimum new durable event/enrollment/work/effect tables and their query-paired indexes;
one worker module and typed domain adapters. No cache, maintained counters, partitioning, or workflow platform.

**Failure behavior:** duplicate events/effects collapse at unique keys; expired leases recover; provider uncertainty
reconciles; backlogs remain visible; hot tenants are capped per claim; organization/channel suspension fails closed;
history remains readable.

**Verification required before 6D closes:** `EXPLAIN (ANALYZE, BUFFERS)` for every query/index pair at the planning
cardinalities; concurrent claim proof with no double claim; event/enrollment/effect duplicate and crash replay;
hot-tenant fairness; 250 event/second intake and 100 due/second execution bursts for five minutes; 100,000 backlog
drain/restart; connection and lock measurements; p95 API list latency, worker lag, rows scanned/returned, payload
size, and cleanup batch impact. Capacity is not established until those workloads pass in a production-like
environment.

**Overall:** Ready for staged implementation after Jafar approves this contract and its workload assumptions.

### 6D-1 query evidence (2026-08-31)

`EXPLAIN (ANALYZE, BUFFERS)` on the managed remote project, each inside a rolled-back transaction that seeded
synthetic volume. Not a capacity claim: these are single-request plans at the cardinalities named below, which
are well under the planning workload. 6D-6 owns the burst, backlog, and concurrency evidence.

| Read/claim | Seeded volume | Plan | Time / buffers |
| --- | --- | --- | --- |
| Event intake claim (`processed_at is null`, `order by seq`, `limit 25 for update skip locked`) | 200,000 processed + 500 pending events | Index Scan `automation_events_pending_idx` -> LockRows -> Limit | 0.143 ms, 29 shared hits |
| Active trigger match (organization + `active_trigger_key`, joined to the pinned version) | 2,000 organizations, 4,000 active recipes + versions | Index Scan `automation_recipes_active_trigger_idx` -> Nested Loop -> Index Scan on the versions unique | 0.082 ms, 10 shared hits |
| Enrollment by record (organization + subject type/id, `updated_at desc, id desc`) | 100,000 enrollments over 200 organizations and 25,000 quote subjects | Index Scan `automation_enrollments_subject_idx` | 0.087 ms, 4 shared hits |

Per-event organization gates (`private.organization_has_automations_feature` plus the
`automation_max_enrollment_duration_days` lookup through `public.effective_automation_limits`) measured warm at
~0.18 ms and ~7.6 shared buffers per event: ~4.4 ms for a 25-event batch. Not a bottleneck; no per-batch
memoization is justified.

Open item carried into 6D-2: `private.automation_events` has no `available_at`, so a repeatedly failing event is
re-claimed on every batch until it is parked at five attempts, and it sits at the head of `seq` order while it
does. 6D-2 adds `available_at` with backoff and moves the partial index to `(available_at, seq)`, which is the
shape this contract's index table already specifies.

### 6D-3a email-effect evidence (2026-08-31)

The email action is real. `advance_automation_work_item` returns `action_due` for an action step; the worker
mints the customer link (Node owns the app origin) and calls `perform_automation_email_effect`, which in one
transaction rechecks pause/expiry, calls the system-authorized `enqueue_automation_quote_email`, and settles.
The send re-checks entitlement, platform authority, quote status, recipient, and sender readiness, renders the
contractor's authored subject/body with only the four allow-listed variables (`customer_name`,
`business_name`, `quote_number`, `quote_link`) filled and HTML-escaped, and enqueues one delivery intent into
the Communications outbox — idempotent on a logical send key derived from enrollment + version + step.
`supabase/tests/database/automation_6d3_email_effect.sql` proves the gate in 23 assertions (sends once, replay
enqueues nothing new, unsafe markup is escaped, a not-ready sender defers, a no-longer-awaiting quote stops the
enrollment). The action step's authoring config changed from a Communications `template_id` to authored
`subject`/`body`; the builder editor and the retirement of the old template-picker path are 6D-3b.

### 6D-6 engine query evidence (2026-08-31)

`EXPLAIN (ANALYZE, BUFFERS)` on the managed remote, rolled-back transaction seeded with 48,000 due work
items across 40 organizations (org 1 hot at 12.5%), ~8,000 parked rows, and 50 dead-letter rows. Plan-level
single-request evidence, not a capacity claim; the sustained-burst, backlog-drain, and concurrency workloads
below remain unverified pending a production-like isolated environment.

| Query (index) | Plan | Time / buffers |
| --- | --- | --- |
| Claim fair-batch candidate window (`automation_work_items_claim_idx`) | Index Scan + Limit 400 → WindowAgg over 400 → sort | 0.75 ms, 11 hits, no spill |
| Claim dead-letter select (`automation_work_items_claim_idx`) | Index Scan → LockRows, limit 25 | 0.11 ms, 68 hits |
| Advance one transition (`automation_work_items_pkey`) | Index Scan → LockRows, 1 row | 0.04 ms, 5 hits |
| Resume parked work (`automation_work_items_attention_idx` + enrollment pkey) | Index Scan → Incremental Sort → Nested Loop, limit 100 | 26 ms, 23.7k hits at 8k parked |

**Bottleneck found and fixed (migration `20260831065617_automation_claim_bounded_candidate_window`).** The
6D-2a claim ranked fairness with `row_number() over (partition by organization_id ...)` and a
`limit v_candidate_window` at the same query level. Postgres evaluates window functions over the full input
before ORDER BY/LIMIT, so the claim Seq-Scanned every pending row, sorted the whole set to disk, ranked all of
it, then trimmed to 400 — 102 ms with an external-merge spill on 48k rows, growing linearly with the backlog on
the engine's hottest path. Fix: take the candidate slice in an inner `candidates` subquery (bounded Index Scan
+ Limit) before ranking it → 0.75 ms, no spill (~135×), O(candidate window) not O(backlog). Behaviour-identical:
the slice is a downward-closed `(available_at, id)` prefix, so each row's per-organization rank within the slice
equals its rank across the whole backlog, leaving the cap decision and final pick unchanged. The 6D-2 pgTAP
suite's claim/fairness/lease/dead-letter/retry assertions all pass on the migrated function; its four
`action_not_available` assertions fail as pre-existing 6D-3 drift (an action step now returns `action_due`),
not from this change.

Minor follow-up (not a blocker): `automation_work_items_attention_idx` is `(organization_id, attention_at desc,
id desc)` while `resume_automation_work_items` orders `attention_at` ascending, so resume cannot stream in index
order and reads the hot organization's parked rows before its limit stops. Bounded and rarely run (manual
recovery). Revisit only if recovery latency becomes material.

**6D-6 still open — capacity not established.** Sustained 250 event/s intake and 100 due/s execution bursts for
five minutes, the 100,000-item backlog drain/restart, concurrent-claim-under-contention with no double claim,
and connection/lock and p95-under-load measurements require a production-like isolated environment (the managed
remote is shared development, not a load target). No capacity claim until those pass there.

## Retention and cleanup

Automation contributes categories to the existing `/jafar/settings/cleanup` area; it does not build a separate
retention product.

| Category | Automation examples | Treatment |
| --- | --- | --- |
| Safe | Superseded claim leases, transient worker diagnostics, rendered previews with no customer record value | Eligible for the shortest policy after terminal state |
| Caution | Step attempts, sanitized errors, skipped/cancelled work details | Previewed and batch-deleted after policy delay |
| Important | Recipe versions, activation/pause/archive audit, enrollment summaries, manual-control history, effect idempotency tombstones | Long-lived; shortening shows operational/audit impact |
| Protected | Customer messages, consent/opt-out/suppression, approvals/signatures, payments, security evidence, immutable access/platform audit | Never deleted as disposable Automation data; owning-domain policy applies |

Platform presets are **Balanced**, **Save more storage**, **Extended**, and **Custom**. Exact Automation retention
durations are approved with 6E after storage and recovery evidence is available. Important summaries and compact
idempotency tombstones cannot be shortened below 730 days; legal and owning-domain rules may require longer.

Shortening policy creates a pending change with actor, reason, old/new value, impact count/estimate, and effective
time seven days later. Cancellation during the window preserves data. Cleanup claims indexed terminal rows in
small id-ordered batches, records progress/failure, yields between batches, and is restartable. It first compacts
Important rows to non-personal tombstones where idempotency/replay protection must outlive detail. Organization
destruction remains the existing separate, stricter workflow.

## Complete desktop UI blueprint

All screens use the existing app shell, `PageContainer`, `PageHeader`, `SectionBlock`, cards, buttons, dialogs,
status badges, tables, skeleton/error/empty primitives, Tabler icons, semantic tokens, SCSS+BEM, and shared focus
behavior. The builder is desktop-first and has no Part 6 mobile completion gate. Server state belongs to TanStack
Query; shell/navigation never waits for page data.

### Settings entry

- Add **Automation** under **Automations, notifications & connections** only when feature + view permission is
  effective and at least one useful recipe journey is enabled. The card says what Automation does; it carries a
  status only for a real condition such as Suspended or Needs attention.
- Hover warms `/settings/automation`. Direct access handles unauthenticated, not-included, permission-denied,
  suspended/read-only, and temporarily unavailable states explicitly.

### Automation home `/settings/automation`

- Page header: title, one green **New automation** action for authorized users, and a secondary **History** link.
- An informative entitlement/limit strip shows effective active recipes and relevant package ceiling without
  presenting safety rules as purchasable allowances.
- Three compact overview cards show Active, Paused/Drafts, and Needs attention. They are links/filters and include
  text as well as status color.
- The main recipe table has Name, Source (Preset/Custom), Trigger, Status, Active enrollments, Last activity, and a
  row menu. Filter chips cover status/source; search is server-side. The name is a real detail link and rows support
  mouse activation. Cursor navigation uses Previous/Next, never page numbers.
- Empty entitled state explains presets and offers **Browse presets** plus **Build from scratch**. Filtered empty,
  no-permission, over-limit, suspended, loading, partial stale data, query error, and retry states are distinct.

### Preset library `/settings/automation/new`

- Header explains presets are editable starting points. Search and domain/channel filters sit above a card grid.
- Each available preset shows purpose, trigger, ordered summary, channels, dependency readiness, and **Use preset**.
  Dependency-blocked presets are absent rather than dead cards. A first card offers **Build from scratch**.
- Choosing a preset creates no server record. It opens the builder with a local draft; the first **Save draft** is
  the first write.

### Builder `/settings/automation/new` and `/settings/automation/[id]/edit`

- Full-page form with breadcrumb/header, recipe name, status context, and the shared pinned form action bar:
  Cancel and **Save draft**. Activation is never a save option.
- Desktop body is an eight-column sequence and four-column summary rail. The sequence contains one bordered
  `SectionBlock` each for **When**, **If**, **Then**, and **Stop when**. The rail shows plain-English timeline,
  recipients/channels, effective limits, overlap/readiness, and estimated maximum messages.
- Cards reveal Basic fields first, Customize fields on request, and Advanced fields last. One card edits at a time.
  Add condition/step uses accessible menus/dialogs; steps reorder through explicit Move up/down controls plus
  keyboard-capable drag enhancement. Order is always available without drag.
- Then steps render numbered Action or Wait cards with summary, edit, duplicate when safe, and remove. Invalid or
  unavailable catalog entries remain visible with a correction path; they are never silently dropped.
- Unsaved navigation warns. Save validates field-level and cross-step errors and focuses the first error. Stale save
  shows the newer editor/time and Review/Discard choices. At/over limit, missing dependency, forbidden action,
  suspended channel, no eligible sender, invalid variable, empty sequence, and unreachable stop behavior all have
  precise inline states.

### Recipe detail `/settings/automation/[id]`

- Read-first header shows status badge, recipe name, preset lineage, active version, last editor/activity, one green
  lifecycle action (Activate, Resume, or Edit as appropriate), and a More menu for pause/archive/duplicate.
- Overview shows the plain sequence, readiness/limits, active enrollments, and Needs attention summary. Active
  definitions are immutable; Edit creates/opens a draft.
- URL-backed underline tabs are **Overview**, **History**, and **Versions**. History and Versions queries remain off
  until tab hover/focus prefetch or activation; a skeleton covers a click that beats prefetch.
- Version comparison identifies changed trigger/conditions/steps/stops and affected new enrollments. Existing
  enrollments clearly retain their version.

### Activation impact review

- A shared accessible dialog is opened only from a saved valid draft. It revalidates on open and again on confirm.
- It shows future-events-only behavior, version changes, effective limits, dependencies/channels, recipients,
  maximum messages/duration, overlapping active recipes, and current active-enrollment treatment.
- Blocking findings disable **Activate version** and link to the owning correction. Warnings require an explicit
  acknowledgement but never hide legal/safety failures. Successful activation navigates to detail and invalidates
  home/detail/access/history caches.

### Global history `/settings/automation/history`

- Cursor-paginated table filters by recipe, record type, state, date, and Needs attention. Rows show occurred/due
  time, recipe/version, record/customer-safe label, current step, result, and attention reason.
- Opening a row reveals an accessible side panel with timeline, attempts, safe reason codes, correlations, and
  record/message links. Customer content, provider credentials, headers, and raw payloads are excluded.
- Loading, filtered empty, expired-detail, forbidden-record, retrying, dead-letter, and retry-command states are
  explicit. Live updates invalidate affected pages rather than creating a second browser cache.

### Record-level Automation controls

- Eligible Quote detail pages gain one `RailCard`/section listing current and recent enrollments with recipe,
  version, next step/time, and state. No eligible/history state is honest and compact.
- Authorized actions are Manual enroll (after preview), Pause, Resume, Skip next step, and Stop. Destructive Stop
  uses a reasoned confirmation. Every mutation has disabled/saving/success/failure feedback and invalidates the
  record, recipe detail, home, and history keys.
- Controls never imply that stopping Automation changes Quote truth or recalls an already accepted message.

### Platform Owner surfaces

- Existing package version editor owns the Automation feature and limit defaults. Draft/publish/retire behavior
  remains versioned; published package history is not rewritten.
- Existing organization detail owns effective values and reasoned/effective-dated feature, limit, action, and
  suspension exceptions. It shows package default, current exception, effective value, author/reason/time, and
  fallback.
- Existing Operations/Communications health surfaces link to Automation backlog, oldest due age, claims, retries,
  dead letters, event lag, and organization hot spots. Recovery commands never bypass live checks.
- Existing Data Retention & Cleanup owns Automation categories, preset/custom policy, seven-day shortening preview,
  batch progress, failure/retry, and protected-category explanation.

### Shared UI state contract

Every owning slice covers loading skeleton, cached/background refresh, empty, filtered empty, API error/retry,
forbidden, not included, read-only, disabled dependency, security suspension, over-limit, stale edit, unsaved
navigation, validation, mutation pending/error/success, partial failure, expired history detail, offline/reconnect,
desktop overflow, 200% zoom, keyboard order/actions, visible focus, screen-reader names, reduced motion, and current
Chrome/Edge/Firefox verification. Dialog/popover focus returns to its trigger. Color is never the only status cue.

## Delivery sequence

- **6B — Entitlements, permissions, limits, and shell:** build the access authority and internally testable access
  states; keep the contractor destination unavailable to ordinary packages.
- **6C — Unified recipe authoring:** implement typed catalogs, drafts, immutable activation, builder, detail, and
  version review without executing customer effects.
- **6D — Engine and Quote follow-up:** add domain events, enrollments, due work, worker/recovery/history, record
  controls, and the first email preset after successful delivery; then expose the destination to approved packages.
- **6E — Retention and cleanup:** extend the central cleanup surface and prove batched cleanup.
- **6F-6H — Dependency-owned packs/actions:** add only through the owning domain/channel contracts.
- **6I — Cross-surface completion:** close remaining security, performance, accessibility, and desktop journeys.

## Deferred scope

- mobile/responsive Automation completion;
- free-form node canvas, branching, parallel paths, loops, scripts, arbitrary HTTP/webhooks, and third-party app
  actions;
- bulk retroactive enrollment and automatic catch-up while paused;
- AI-authored or AI-executed recipes;
- SMS until Communications SMS consent, registration, balance, quiet-hours, eligibility, delivery, and charge
  contracts are active;
- invoice, payment, Job/review, Scheduling, lead, missed-call, booking, receipt, and Website Chat packs until each
  owning dependency is approved and real; and
- partitioning, external workflow engines, or Redis correctness until measured evidence requires them.

# Jobs campaign roadmap

Jafar authorized this campaign on 2026-08-31 and approved parts incrementally. The campaign paused after
Part 11b on 2026-09-02 while Schedule proceeds and Invoice-dependent work waits for its contract.

| Part | Outcome | State | Dependency | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Live Jobber tour and comparison to existing Jobs structures | Complete 2026-08-31 | Jobber and app access | Major Jobs branches captured and evidence boundaries explicit |
| 2 | Feature-preserving simplification and implementation sequence | Complete 2026-09-01 | Part 1 | Jafar approved the UpliftContractor direction |
| 3 | Approve the Jobs behavior contract and minimum boundary | Complete 2026-09-01 | Parts 1–2; explicit schema/RLS approval | Job, Visit, pricing, status, permissions, tenant boundaries and Quote lineage are precise |
| 4 | Build Job identity, lifecycle, permissions and tenant foundation | Complete 2026-09-01 | Part 3 | Isolation, allowed states, numbering and protected financial fields verified |
| 5 | Build Job-owned scope and atomic Quote-to-Job conversion | Complete 2026-09-01 | Part 4; approved Quote contract | Accepted scope copies once without duplicate Jobs or rewritten Quote history |
| 6 | Deliver the Jobs list and bounded read model | Complete 2026-09-01 | Part 4 | Filters, operational states, pagination, permissions and feedback states verified |
| 7 | Deliver direct one-off Job creation | Complete 2026-09-01 | Parts 4–6 | One Job creates with client/property, scope and 1–20 Scheduled/Anytime/Unscheduled Visits |
| 8 | Deliver Job detail structure and safe staged editing | Complete 2026-09-01 | Parts 5–7 | Detail structure, history, staged editing and permission shaping verified |
| 9a | Deliver Visit scheduling commands and API | Complete 2026-09-01 | Parts 7–8 | Permission, idempotency, revision and completed-Visit protection verified |
| 9b | Deliver Visit scheduling UI on Job detail | Complete 2026-09-01 | Part 9a | Add, edit, duplicate, delete and bulk date moves are permission-shaped and verified |
| 10 | Deliver recurring and as-needed scheduling | Complete 2026-09-01 | Part 9 | Recurrence, zero-Visit as-needed work and all edit scopes preserve completed history |
| 11a | Edit a saved Job's scope and billing setup | Complete 2026-09-01 | Parts 5, 8, 10 | Scope, pricing basis, invoice timing, discount and tax edit honestly |
| 11b | Invoice reminders and Requires invoicing | Complete 2026-09-01 | 11a | Reminder rules drive derived status and clear only through their approved resolution |
| 11c | Payment installments and per-visit amounts | Transferred to the Invoices campaign as Part 5c on Jafar's approval 2026-09-05; build it there, not here | 11a; Invoices 5a | One-off installments total the Job; per-visit quantities exist only under per-visit pricing |
| 12 | Supply Jobs-owned Visit truth to the unified Schedule | Transferred to Schedule campaign 2026-09-02; not feature-complete | Parts 9–10; Schedule foundation | Schedule reads and invokes the existing Visit truth, permissions, recurrence and commands without a second Visit store; implementation and calendar UX are owned by the Schedule campaign |
| 13a | Deliver Jobs-owned Visit completion and Job lifecycle primitives | Complete 2026-09-03 | Parts 8–10, 11b | Complete/uncomplete Visit and final-Visit Finish job/Add a return visit/Keep open consequences are idempotent, preserve completed history, and emit durable events; marking a Visit complete fires the per-visit reminder when configured and finishing a Job fires the on-completion reminder |
| 13b | Deliver Invoice handoff | Transferred to the Invoices campaign 2026-09-05: the job_total handoff is Invoices 5a, the visit/period handoff and Invoice now/later are Invoices 5b | 11c, 13a; Invoice seam | Invoice Now/Later and Invoice creation/resolution preserve billing truth; creating an Invoice resolves the matching reminder with resolution='invoiced' |
| 14a | Costing foundation: protected hourly-rate store, time entry and expense tables, append-only correction trail, receipts on the shipped attachment subsystem, and the four record-vs-see permission keys | Complete 2026-09-07 | Part 8 | RLS on every table, no money column in any `authenticated` grant, append-only trail refuses update and delete |
| 14b | Labor: time entry commands, API, and the Job detail Labor section | Complete 2026-09-07 | 14a | Rate snapshots at recording time, own/team permissions shape every action, and every change appends to the trail |
| 14c | Expenses: commands, API, and the Job detail Expenses section with receipts | Complete 2026-09-07 | 14a | Jobber's field set saves, receipts accept images and PDFs through R2, and own/team permissions shape every action |
| 14d | The costing panel: one authoritative profit for a one-off Job | Complete 2026-09-07 | 14b, 14c | `job_money` no longer reports a profit that excludes labor and expenses; margin, zero-revenue and in-progress states behave as approved. `job_costing` reader folds item + labor + expense cost against revenue-before-tax; own `JobCostingCard` in the rail; recurring jobs get no all-time figures (deferred to 14e); verified in the browser (open-state wording, no margin while open, live update on record/remove) |
| 14e | Recurring Job costing over the rolling 30-day window | Planned | 14d | `per_visit` and `fixed_per_period` each pair costs with the revenue their pricing basis defines, and the window is named on screen |
| 15 | Deliver notes, attachments/photos, checklists, signatures, and proof of work | Planned | Parts 8–10; attachment storage | Field records retain staged-save, access, history, preview, and mobile/offline requirements owned by their subsystems |
| 16 | Verify integrated contractor journeys, recovery and measured performance | Planned | Jobs-owned Parts 4–11c, 13a–15; Schedule Part 5 parity | Approved Jobs journeys pass; Schedule parity is verified; affected growth paths have proportional evidence; remaining external dependencies are explicit |

Jobber evidence belongs in its domain reference and `Design/Jobber Jobs/`; proposal details belong in `docs/research/`, not Memory.

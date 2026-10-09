# 4 — Booking confirmation

**Campaign:** client-reminders · **Plan:** `docs/client-reminders-behavior-contract.md` § "You're booked" confirmation, § Customer messages: shared rules
**Code:** worktree `/home/jafar/Ucrm-cr4`, branch `client-reminders-4`
**Done when:** Booking a visit sends one confirmation; a recurring job sends one, not one per visit; moving it sends one update; unticking sends nothing.

## Design (technical, chosen 2026-10-09)

- Two new triggers, `appointment.booked` and `appointment.rescheduled`, on the Part 3 subject (job visit or
  assessment), reusing its intake, stops and `action.send_appointment_email`. Two presets: "Booking
  confirmation" and "Visit moved", off by default.
- Database triggers log every schedule change (scheduled / moved / removed) on visits and assessments into
  `private.appointment_schedule_changes`, with who made it. Each scheduling route then calls
  `settle_appointment_notices(subject, notify)` with the tick box value (default false): it settles that
  person's recent changes and, when ticked, emits at most one event — booked (first time, one per job or
  assessment ever) or rescheduled (already booked, and something moved or the recurring schedule was rebuilt).
  Adding or removing a visit alone sends nothing.
- A rescheduled email is skipped if the visit moved again before it went out (the newer move sends).
- Tick box shows only while the matching automation is on (extend `/api/clients/message-automations`).
- Screens: JobForm, JobVisitsSection (add, edit, recurring change, apply to future), schedule page (drag
  proposal, drawer edit, add visits, new job, place backlog visit), RequestForm and request assessment panel.
- Migration version `20261113090000` (C3 and E1 hold nearby numbers).

## Steps

- [x] Migration written
- [x] Catalog, presets, routes (Zod `notify_customer`), status endpoint `/api/schedule/customer-notices`
- [x] Tick box on every scheduling screen (`NotifyCustomerCheckbox`); type check clean; branch pushed
- [ ] Unit tests
- [x] Applied 2026-10-09 through `execute_sql` (the `apply_migration` tool kept failing with "Invalid or expired requestState"); live function bodies match the file (outcome check: `select version from supabase_migrations.schema_migrations where version = '20261113090000'`)
- [ ] Prove in the app; merge to `main`; remove worktree

## Next

Unit tests for the new triggers and presets (`src/lib/server/automation/definition.spec.ts`, `catalog.spec.ts`), then prove in the app on Raad LTD: turn on the two presets, book a job (one email), recurring job (one), move a visit (one), untick (none). Then merge to `main`.

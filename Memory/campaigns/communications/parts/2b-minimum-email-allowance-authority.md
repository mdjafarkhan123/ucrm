# Part 2B: Minimum Email Allowance Authority

## Outcome

Before any operational email can leave UCRM, the worker can decide atomically whether that organization has
room in its package allowance or protected-essential reserve for the current subscription period. The live
send route remains deliberately disabled until this outcome passes.

## Approved behavior

- Package email is included in the subscription and never draws down Twilio Communication Balance.
- Each subscription period has exact UTC start and end timestamps. A package change does not silently open a
  fresh allowance period.
- An accepted unique recipient consumes one allowance unit. Replays of the same logical send never consume a
  second unit; validation failures consume none.
- Optional operational mail uses the normal allowance. Essential contractor mail (requested quotes,
  invoices, receipts, security notices, and direct human replies) may use its separate protected reserve.
- When both applicable capacity sources are exhausted, the message stays queued and is reconsidered before
  any later release.
- Jafar owns package defaults and can set a numeric, inherited, unlimited, and effective-dated organization
  override with author and reason. A full Jafar capacity/reputation console remains Part 7.

## Ordered slices

### 2B-A. Period and allowance authority — active

- Add exact subscription-period authority; do not infer it from `paid_through_date` alone.
- Extend the existing package-limit and organization-limit override model with the two email values needed
  now: normal recipient allowance and protected-essential recipient reserve.
- Add one server-only database resolver for an organization's current period and effective two allowances.
- Preserve the existing commercial-state and package-assignment seams; a package change remains a change
  within the current period unless an explicit billing command opens the next one.
- Add indexes for organization/current-period lookup and effective override lookup. Verify tenant isolation,
  direct-write denial, idempotency, overlap prevention, and query plans.

### 2B-B. Atomic outbox integration

- Fold the period/allowance resolver and Part 1 accepted-recipient usage into the existing atomic outbox
  claim. Return a safe queued/deferred result when capacity is unavailable.
- Recheck capacity at claim time; do not trust a prior preview or caller-provided counts.
- Keep provider calls outside transactions and keep the live worker fail-closed until the gate passes.

### 2B-C. Platform Owner controls

- Add Jafar controls for each package's normal allowance and protected-essential reserve, plus a clear
  effective-value readout for an organization and its current period.
- Add Jafar controls for a numeric, inherited, unlimited, and effective-dated organization override, with
  author and reason. The controls change stored authority; no email limit is hardcoded in application code.
- Defer global provider capacity, reputation controls, emergency controls, and advanced reporting to Part 7.

## Decisions and risks

- `organization_commercial_state` stores a paid-through **date**, not the required exact period boundary.
  It cannot be used as the sole period identity.
- Existing `organization_limit_overrides` has only the `employee_seats` key and a one-row-per-key shape.
  The migration must either safely generalize the authoritative commercial override seam or introduce a
  deliberately scoped append-only email override history; do not duplicate two competing resolvers.
- The period boundary must be written by a billing/commercial command, never guessed from a calendar month,
  timezone, or package name.
- This part is a minimum safety gate, not the wider Part 7 provider-capacity/reputation system.

## Completion gate

- The pre-send claim can atomically resolve the active UTC period, effective allowance/reserve, and existing
  accepted-recipient usage for one organization.
- Optional mail cannot consume protected reserve; essential mail is queued once its reserve is exhausted.
- Package and override changes do not create a fresh period or double-count a retry.
- Database tests, relevant query plans, privileges/RLS checks, generated types, focused service/API tests,
  and the database/API performance reviews pass.
- The worker remains fail-closed until the complete Part 2B gate is met.

## Source pointers

- `docs/contractor-email-contract.md` §§ Package allowances and counting; queueing and worker claim
- `Memory/campaigns/communications/parts/1-email-delivery-foundation.md`
- `src/lib/server/communications/email-worker.ts`
- `supabase/migrations/20260813103456_organization_commercial_control_foundation.sql`
- `supabase/migrations/20260826090000_employee_seat_limit_authority.sql`

# ADR 0008: Jafar Panel teammates are a separate login, sharing the owner's session registry

## Status

Accepted 2026-10-07, with Jafar business management part D1. Follows § Team access across `/jafar` of the
[Jafar business management plan](../jafar-business-management-behavior-contract.md) and extends
[ADR 0007](0007-jafar-panel-front-door-gate.md).

## Context

Jafar invites Uplift teammates (Sales, Delivery, Support, Platform Operations) to `/jafar`. They sign in with
email and password, reset a forgotten password by email, and lose access the moment Jafar removes them.
Contractors already have Supabase Auth accounts, scoped to their organization by membership and RLS. The
Jafar owner is not a Supabase user: a configured email and password hash, a signed `jafar_session` cookie
carrying only a session id, and the `platform_owner_sessions` registry that the gate checks on every request.

## Decision

1. **Teammates are not Supabase Auth users.** They live in `platform_team_members` with their own bcrypt
   password hash. Staff and customer identities are kept apart, the usual pattern for a vendor's internal
   console versus its customers' accounts:
   - A teammate who also owns a contractor business keeps two unrelated logins, so neither one opens the other.
   - A Supabase session cookie, which every contractor route trusts, never grants `/jafar` access.
   - The contractor invitation's "email already registered" rule is not affected.
2. **One session registry and one cookie.** A teammate session is a `platform_owner_sessions` row with
   `team_member_id` set and `owner_email` holding the teammate's email. The owner's row keeps
   `team_member_id` null. `getOwnerSession` resolves both, so ADR 0007's single gate, the Support live
   channel grant, and every route's `session.email` audit field work unchanged.
3. **Removal is immediate.** The registry lookup on every request requires the member to be `active`, and
   removal also revokes the member's open sessions. Supabase JWTs could not do this: `getClaims` trusts a
   token until it expires.
4. **Areas are decided by path at the gate.** `src/lib/jafar/team-access.ts` maps each `/jafar` and
   `/api/jafar` path to an area and each role to its areas with a level: *look* (GET only) or *work*. An
   unmapped path is owner-only (deny by default). The same module filters the sidebar, so screens and server
   agree. D2's per-teammate switches change the role's default set, not the mechanism.
5. **Tokens follow OWASP.** Invitation and reset links carry 32 random bytes. Only their SHA-256 is stored;
   each is single-use, consumed by one conditional `UPDATE`, and replaced when a new one is issued. An
   invitation lasts 7 days and a reset 1 hour. The forgot-password answer is the same whether or not the
   email exists, and a reset signs out the member's other sessions. Their pages send no referrer.
6. **Only the owner has step-up and the owner's powers.** `/api/jafar/reconfirm` verifies the configured
   owner password and stays owner-only, so every step-up-protected action remains Jafar's.

## Rejected

- **Supabase Auth users with a staff flag.** These would share the contractor cookie and identity pool, they
  could not be cut off instantly, and the Supabase password-reset emails and pages point at the contractor app.
- **A second session table or cookie for teammates.** It would mean a parallel check beside ADR 0007's gate.
- **Per-route permission checks.** About 150 handlers would each need one; a forgotten one would open a
  route.

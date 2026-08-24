# Part 3A: Access and data foundation

Approved by Jafar 2026-08-25 after four design revisions. **Scope is database foundations only:** schema,
status enforcement, grants, seat authority, command primitives, direct database tests, and replacing the
internals of the two team API routes that already exist. **No 3B or 3E orchestration under this approval.**

## Corrections that shaped the design

These overturned earlier assumptions and must not be re-litigated:

1. **No domain enforces assigned scope, and "Clients owner-assignment" was never the mechanism.**
   `private.client_is_assigned_to_current_user` is a stub returning `false`; it was always meant to key off
   Visit/Job assignment (see its 2026-08-16 comment), gated on Scheduling, not on a client-level owner.
   Confirmed against Jobber 2026-08-24: Jobber has no persistent client owner at all — ownership lives on
   each work object separately (Request/Quote `salesperson`, matched by our `opportunities.owner_user_id`)
   and resets at every stage. `clients.owner_user_id` was speculative, written by no code path, and was
   removed rather than built out (`supabase/migrations/20260902140000_remove_client_owner_no_jobber_precedent.sql`).
   3A ships the scope representation with every permission at `scope_model = 'none'` and the database
   refusing `assigned`; the assigned-work seam activates only when Scheduling lands.
2. **Permanent removal cannot delete the login account.** 24 authorship columns reference `auth.users` with
   `on delete no action`, so deletion fails for anyone who has ever done anything. Removal is a tombstone.
3. **A policy helper must keep `EXECUTE` for `authenticated`.** Policy expressions are evaluated as the
   querying user, so revoking it breaks every read the policy guards. Only non-policy helpers
   (`member_has_permission`, `member_permission_scope`, trigger functions) are fully locked down.
4. **There is no supported admin call to end another user's sessions.** `admin.signOut(jwt)` needs the
   user's own JWT. Denial depends on membership status; `ban_duration` is belt-and-braces; **never write to
   `auth.sessions`.**
5. **Seat limits have one authority.** The SQL resolver is authoritative and `effective.ts` consumes it.
   TypeScript keeps only presentation mapping.

## Done and verified (each in a rolled-back transaction)

| Migration | Proves |
| --- | --- |
| `20260825090000_team_membership_lifecycle` | four states, business fields, two revisions, cleanup ledger; at-most-one-owner partial unique index; deferred exactly-one-owner constraint trigger |
| `20260825090100_membership_status_authorization_seam` | `status = 'active'` in the five known helpers |
| `20260825090200_two_policies_that_bypassed_the_seam` | `notes` author branch and `profiles` teammate branch now require active membership |
| `20260825090300_permission_scope_representation` | scope columns, `assigned` refused for every key, resolvers ready |
| `20260825090400_membership_lookup_once_per_query` | the sixth and seventh helpers (`member_organizations`, `validate_client_owner`) join the seam; notes policy stays per-row on measured evidence |

Verified: zero-owner rejected at commit, ownership swap inside one transaction accepted, second owner
rejected immediately. A 54-table RLS sweep shows a deactivated member reads **zero** tenant rows; only
global reference tables and their own profile row remain visible.

## Remaining work, in dependency order

1. ~~**Seat limit resolver.**~~ `public.effective_employee_seat_limit(org, at)`, security invoker, lives in
   `public` rather than `private` because PostgREST only exposes `public` and `effective.ts` calls it
   directly. `20260826090000` (superseded), `20260826090100`.
2. ~~**Seat counting and the invitations table.**~~ Seats used = memberships in (`pending`, `active`) plus
   invitations in `reserving`. `assert_employee_seat_available` takes `pg_advisory_xact_lock` on the
   organization -- transaction-scoped, so it is safe under Supavisor transaction-mode pooling. Invitation
   states are `reserving -> invited -> accepting -> accepted`, or `cancelled`/`expired`/`abandoned`.
   `20260826100000`, which also restored the four policy helpers' `authenticated` EXECUTE.
3. ~~**The invitations table's 11 service_role primitives.**~~
   `mark_team_invitation_auth_attempt_started` is deliberately separate from `begin_team_invitation`, so a
   crash before an Auth call is never mistaken for a possibly-created identity. `20260827090000`,
   `20260827090100`; `supabase/tests/database/team_invitation_service_role_primitives.sql`.
4. ~~**`organization_member_access_events` and the `member_access_event_shapes` allow-list.**~~ The five
   summary value kinds are closed vocabularies and there is no text kind at all, which is what makes
   permanent-removal identity structural rather than a convention. Deliberately not merged into
   `public.access_audit_events`, which already stores emails and free-text reasons. `20260828090000`,
   `20260828090100`, `20260828090200`; `supabase/tests/database/team_member_access_events.sql`.
5. ~~**`organization_ownership_transfers` and its three commands.**~~ Who ends a pending handover is decided
   by the database, not passed in: the requester closing it is `cancelled`, the recipient closing it is
   `declined`. Request changes no roles at all. Accept re-checks both sides at the moment it acts, and
   demotes the old owner before promoting the new one. **For item 8 and 3E:** a read of this table without
   an `organization_id` filter seq-scans, so every API read must filter by organization explicitly.
   `20260829090000`; `supabase/tests/database/team_ownership_transfer_commands.sql`.
6. ~~**The seven member commands.**~~ Role and permission saves take `expected_access_revision`, the details
   save takes `expected_profile_revision`, and a stale editor is refused with `40001`. A save that changes
   nothing writes no history and bumps no revision. Deactivation is refused for a pending invitee (cancel
   the invitation instead), so restore never has to guess which state to return to. Removal is owner-only
   and is a tombstone. A member's `full_name` lives on `public.profiles`, one row per person across every
   organization, so a null name means "leave it alone" rather than "clear it" -- Jafar was told this and
   accepted it. `20260830090000`, `20260830090100`, `20260830090200`;
   `supabase/tests/database/team_member_commands.sql`.
7. ~~**Grant cleanup, then the function-grant matrix test.**~~ Done 2026-08-31. The eight tables were
   `organization_members`, `organization_member_invitations`,
   `organization_member_permission_overrides`, `organization_settings`, `organization_settings_audit`,
   `organization_business_hours`, `permissions` and `role_permissions`; the three newest tables were
   already clean from their own migrations. `20260831090000` takes every write privilege off `anon` on all
   eight, and off `authenticated` on the six whose writes already run through a definer command.
   **The deliberate exception, which item 8 must close:** `authenticated` keeps its write grants on
   `organization_members` and `organization_member_permission_overrides`, because
   `PATCH /api/team/members/[userId]` and
   `PUT /api/team/members/[userId]/permissions/[permissionKey]` still write those tables as the signed-in
   user. Jafar chose this on 2026-08-31 so the app never spends a commit with those two screens broken;
   the matching revoke belongs in item 8's migration, and the matrix test's expectations change with it.
   Two live bugs surfaced, each fixed in its own migration with the reasoning in its comments:
   `20260831090100` -- `effective_employee_seat_limit` had EXECUTE for `authenticated` only, so every
   `/jafar` organization route, which resolves access with the service_role client and throws on any failed
   query in that batch, was answering 500; the same migration locks `private.validate_client_owner`, the
   last seam helper still carrying the default PUBLIC execute. `20260831090200` -- the three Part 1
   settings write commands are SECURITY DEFINER and were executable by `anon`, so PostgREST published them
   to anyone holding the publishable key; their internal `has_permission` check refused a signed-out caller
   (confirmed live), so nothing was ever at risk, but a definer write should not have a signed-out request
   in front of it at all.
   `supabase/tests/database/team_function_grant_matrix.sql` names all 42 functions the part ships or
   depends on and asserts a yes or no for each of `anon`, `authenticated` and `service_role`. It uses
   `has_function_privilege` rather than the grants view, because that also catches a grant inherited from
   PUBLIC. All 129 assertions pass in one rolled-back transaction. Two findings outside 3A's scope are in
   `Memory/deferred/INDEX.md`: eleven older `private` trigger functions still executable by everyone, and
   seven `public` security-invoker functions still reachable by `anon`.
8. ~~**Route internals.**~~ Done 2026-09-01, closing 3A. `PATCH /api/team/members/[userId]` calls
   `change_team_member_role`; the per-permission route (it was `PATCH .../permissions/[permissionKey]`, not
   `PUT`) is gone, replaced by `PUT /api/team/members/[userId]/permissions` calling
   `save_team_member_permissions`. Both go through `getTeamCommandClient()` in
   `src/lib/server/access/team-commands.ts`, which also holds the one error map both share: `40001` becomes
   a 409 carrying `stale: true`, `23514` a 409, `P0002` a 404, and anything else a 500 that says nothing
   about the member. The routes now check who is asking and what was sent, and nothing else -- the authority
   and last-owner rules they used to repeat live only in the commands. `GET /api/team/members` returns
   `status` and `access_revision` per member, because a screen that never saw the revision can only save
   blind. `20260901090000` takes the held-back write grants off both tables and drops the redundant
   overrides index Jafar approved the same day. The matrix test grew sections 6 and 7 for that -- eight
   tables by anon and authenticated, plus the dropped index -- and is now 146 assertions, all passing.
   `getOrganizationContext` filters `status = 'active'`, so a pending, deactivated or removed member gets no
   organization anywhere in the app; `src/lib/server/auth/organization.spec.ts` proves it. Types regenerated
   and byte-identical, `npm run check` clean, 898 unit tests passing.

## Invariants per state

| State | Auth user | Membership row | Invitation row | Seat |
| --- | --- | --- | --- | --- |
| `reserving` | no | **no** | yes | consumes (a reservation, not a member) |
| `identity_created`…`accepting` | yes | `pending` | yes | consumes via membership |
| `accepted` | yes | `active` | terminal | consumes |
| `cancelled`/`expired`/`abandoned` | deleted by 3B | deleted | retained | none |
| — | banned | `deactivated` / `removed` | — | none |

## Acceptance is two-phase and lease-guarded

`claim_team_invitation(token_hash, email, lease_nonce, lease_seconds)` — one atomic UPDATE, succeeds only
from a sendable state **or** an `accepting` row whose `lease_expires_at` has passed. Then Auth sets the
password carrying its own receipt in `app_metadata.invitation_password_set_for = <invitation_id>`. Then
`record_invitation_password_set` and `finalize_team_invitation`. Membership stays `pending` — denied by all
seven helpers — until finalize commits. Retry after a crash calls **finalize only**, never the token,
never the password.

**3A ships these primitives and claims nothing about recoverability.** Reading the Auth receipt is
orchestration; the guarantee belongs to 3B along with a live test that `updateUserById` writes password and
`app_metadata` atomically.

## Orphan rule

The API stamps `auth_attempt_started_at` immediately before calling Auth. The sweep may release the seat and
mark `abandoned` **only** when that column is null. Otherwise it sets `identity_cleanup_state = 'required'`
and stops: the seat stays held and the email stays claimed, enforced by a partial unique index on
`lower(invited_email)` over non-terminal invitations. Deleting the orphan Auth account is 3B's worker.

## Ownership transfer has no bypass

Three layers, none trusting the caller: `authenticated` holds no write grant, so only SECURITY DEFINER
commands write; each command refuses owner targets and owner promotion explicitly; the partial unique index
and the deferred trigger prove at-most-one and exactly-one independently. The transfer command demotes the
old owner **before** promoting the new one inside one transaction.

## Permanent removal identity

Dead email is `removed+{user_id}@removed.invalid` — RFC 2606 reserved, 61 characters, collision-free,
idempotent to re-apply. Nothing displayed reads the Auth email: attribution reads `profiles.full_name`, with
`display_name_at_removal` as the snapshot. Audit summaries carry no free text, enforced by the shape
allow-list, so no email or name can enter that table.

## Completion gate

Schema, commands, RLS, grants, indexes and direct database tests prove: tenant isolation on every new
object; exactly one owner per organization, protected against every write path and against zero owners at
commit; membership status denies pending, deactivated and removed members at all seven helpers and every
table policy; seat limits resolve from a single SQL authority the display path consumes, and hold under
concurrent reservation; acceptance is two-phase, single-use and race-safe, granting no access until
finalization; permanent removal preserves attribution without depending on the Auth email; the scope
representation refuses `assigned` for every key, because **no domain truthfully supports assigned scope
yet**; and no write grant remains for `anon` or `authenticated` beyond what the existing APIs need.

`getOrganizationContext`, the replaced routes and the seat display mapping are proven by Vitest, not by
database tests. End-to-end invitation delivery, acceptance, session revocation, permanent removal and
re-invitation are **not** claimed by 3A.

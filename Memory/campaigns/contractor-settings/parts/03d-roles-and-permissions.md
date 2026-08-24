# Part 3D: Roles & permissions

## Outcome

Owners and Administrators can understand a person's standard role, safely change it when their authority
allows, and make bounded individual permission adjustments without seeing raw database keys. The database
commands remain the only authority for role and access changes.

## Approved behavior

- Standard roles are Administrator, Office, Sales, Field, and Finance. Ownership is never selectable.
- Owners alone promote, change, or demote an Administrator; Administrators manage Office, Sales, Field, and
  Finance members. Nobody edits their own role or permissions.
- A role change previews standard access and lets the manager choose standard access or retain only compatible
  individual adjustments. The preview names removed adjustments.
- Controls are grouped as understandable capabilities, with plain examples and dependency help in an
  accessible information popover. Database permission keys never leave the server boundary.
- An individual difference marks the member as Adjusted. A plan-unavailable capability is disabled as Not
  included in your plan; saved adjustments remain stored but grant no access until the entitlement returns.
- Invitations, ownership transfer, offboarding, assignment scope, availability, and activity remain out of
  scope.

## Existing truth to reuse

- `public.change_team_member_role` is the atomic, revision-protected role command. Its compatible-adjustment
  rule is authoritative.
- `public.save_team_member_permissions` replaces the complete adjustment set atomically and records one
  access-history summary. Both commands are service-role-only and reached only through existing API routes.
- `PATCH /api/team/members/[userId]` and `PUT /api/team/members/[userId]/permissions` already validate and
  call those commands. Do not create a second write path.
- `src/lib/server/access/effective.ts` resolves role permissions, overrides, and plan entitlement state. A
  bounded read-only API may reuse it on the server.

## Implementation checklist

- [x] Add one read-only access-editor API model behind the Team-manager guard. Return role labels/summaries,
      capability descriptors, effective availability, adjustments, and exact revision only.
- [x] Add typed Team API queries/mutations and exact Team detail/directory cache invalidation after saves.
- [x] Turn Settings' Roles & permissions destination into a permission-aware link and warm its route.
- [x] Build the member-detail editor entry point; preserve skeleton, error, and 409 recovery.
- [x] Use native controls for simple choices and the installed Bits UI popover for capability help.
- [x] Add focused API/client coverage, run Svelte autofixer, formatting, build, and API/TanStack/Svelte
      performance gates.
- [x] Complete the live browser gate; Jafar accepted all remaining checks on 2026-08-24.

## Read-model boundary

The browser receives named capabilities and permitted controls, not `permission_key` values. The server owns
the mapping to existing keys and validates every submitted control against the editor model before calling the
existing command. The fixed catalog bounds the response; there is no unbounded user list or per-control request.

## Risks

- The role command decides the actual result; a preview may only use the same role/default and override data.
  A stale save keeps the existing 409 and retains the draft.
- A service-role read stays behind `requireContractorTeamAdmin`; it never reaches browser code or returns
  sign-in, Auth, cross-tenant, or raw-key data.
- Capability copy must be explicit project copy, not inferred from dotted key names. Stop for Jafar if the
  existing catalog cannot be grouped honestly.
- Any need for SQL, a migration, index, or RLS change is a scope change requiring separate approval.

## Completion gate

Every visible choice produces exactly the effective authorization described; plan-disabled controls cannot
grant access; stale, self-escalating, cross-tenant, and unauthorized saves fail at API and database boundaries.
Owner/Administrator/ordinary-role visibility, keyboard-accessible help, conflict recovery, mobile layout, and
performance checks pass.

## Closing verification

The earlier Administrator-display failures were corrected in the client while the command and read-model
boundaries continued enforcing the same rules. Jafar confirmed on 2026-08-24 that all remaining live browser
checks passed. Part 3D is closed.

## Source pointers

- `docs/contractor-settings-blueprint.md` → **Confirmed Part 3 behavior**.
- `parts/03-team-and-access.md` → 3D scope and safeguards.
- `src/routes/api/team/members/[userId]/+server.ts` and `permissions/+server.ts` → write paths.
- `supabase/migrations/20260830090000_team_member_commands.sql` → atomic role/permission rules.

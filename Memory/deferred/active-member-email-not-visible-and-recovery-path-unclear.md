# Active member's sign-in email is not visible in the Team directory, and recovery path is unclear

- **Priority:** P2


- **Campaign:** `contractor-settings` (Part 3, Team & Access)
- **Reason:** Jafar tried to help browser-verify two Quote Settings (Part 2C) checks that need a
  non-owner test login (the existing `field` member) but could not recover access: he has forgotten
  that member's password, the Team directory shows no email column for an already-active member
  (`member.invitation?.email` in `src/routes/(app)/settings/team/+page.svelte` only exists for a
  still-pending invitation, so there is no way to see which address to reset), and he could not find
  a way to delete the member and re-invite a fresh one. Whether member deletion actually exists and
  is just not surfaced where he looked, or is genuinely gated (Part 3's offboarding/reassignment gate
  in `Memory/campaigns/contractor-settings/NOW.md` — "Assigned-scope and offboarding reassignment
  remain gated on the Clients owner-assignment workflow" — may be the cause), was not confirmed this
  session.
- **Confirmed 2026-08-24:** an active member's row/detail page shows no email anywhere (only
  `member.invitation.email`, null once active). No deactivate/remove function exists anywhere in the
  codebase or migrations — genuinely not built (this is Part 3E, still pending; see
  `Memory/campaigns/contractor-settings/NOW.md`), not just a reassignment-gate block. The immediate access
  wall was worked around this session by resetting the `field` account's password directly via SQL
  (pgcrypto `crypt()` against `auth.users`) rather than through any in-app recovery path, since no admin
  reset tool is exposed through the Supabase MCP server.
- **Reactivation trigger:** Jafar or the agent wants to design an in-app email-visibility/recovery path for
  active members (not just SQL workarounds), or Part 3E (deactivate/remove UI) is scoped and built.
- **Checkpoint:** `Memory/campaigns/contractor-settings/parts/03-team-and-access.md`,
  `Memory/campaigns/contractor-settings/parts/03c-team-directory-and-member-details.md`

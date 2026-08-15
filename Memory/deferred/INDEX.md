# Deferred Work

Only unresolved work explicitly postponed by the user belongs here.

## Prospect detail page

- **Campaign:** `operations-prospects-ux`
- **Reason:** The user paused the Prospect work after the reusable dialog and Operations conversion were completed.
- **Reactivation trigger:** The user explicitly asks to resume the Prospect detail page.
- **Prerequisites:** Reinspect the current Prospect list, APIs, mutations, and organization-detail route before implementation because old line references are stale.
- **Checkpoint:** `Memory/campaigns/operations-prospects-ux/NOW.md`
- **Part packet:** `Memory/campaigns/operations-prospects-ux/parts/03-prospect-detail-page.md`

## Non-admin email-correction browser verification (Part 7)

- **Campaign:** `jafar-panel`
- **Reason:** No organization on the platform currently has a non-owner/non-admin (office/sales/
  field/finance) member -- every seeded org has exactly one member, the owner. The "Fix profile"
  email-change branch for non-admin roles is covered by an automated test
  (`profile-correction.spec.ts`) and code review, but has never been exercised live in the browser.
  Jafar explicitly chose to close Part 7 without this check rather than create throwaway test data.
- **Reactivation trigger:** A real organization gets a non-owner/non-admin member (through normal
  product use, or a deliberate throwaway test member), and Jafar or the agent wants to confirm the
  email field renders and the email-change PATCH round-trips live.
- **Prerequisites:** None beyond a qualifying member existing.
- **Checkpoint:** `Memory/campaigns/jafar-panel/parts/7-team-access-and-administrator-recovery.md`
  (closed packet, kept for this deferral's context).

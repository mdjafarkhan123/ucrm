# Non-admin email-correction browser verification (Part 7)

- **Priority:** P3


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
- **Pointer:** `docs/jafar-completion-contract.md` and the current profile-correction implementation.


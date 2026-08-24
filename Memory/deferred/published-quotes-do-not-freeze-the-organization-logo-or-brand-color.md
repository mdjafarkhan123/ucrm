# Published Quotes do not freeze the organization logo or brand color

- **Priority:** P1


- **Campaign:** `contractor-settings` Part 1, corrected by Jafar 2026-08-22. Owned by `quotes`.
- **Reason:** `quote_versions` snapshots `organization_name` only. Replacing or removing the logo would
  change or break a proposal a customer already received. Settings work must not touch the dirty Quotes
  worktree, so the snapshot cannot be added from Part 1.
- **Reactivation trigger:** the `quotes` campaign resumes, or any customer-facing document work starts.
- **Prerequisites:** add the logo object key and brand color to the published version, serve them through the
  existing `/q/[token]` access-link path using `src/lib/server/settings/logo.ts`, and keep the delivery
  token-scoped rather than publicly readable.
- **Acceptance test:** a published document keeps its original branding after the organization replaces its
  logo and brand color. Contractor Settings Part 1 is not complete until this passes.
- **Checkpoint:** `Memory/campaigns/contractor-settings/parts/01-settings-foundation-and-business-profile.md`,
  `src/routes/(public)/q/[token]/files/[attachmentId]/+server.ts`.


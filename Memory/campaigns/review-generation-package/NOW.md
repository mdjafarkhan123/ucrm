# Review Generation package — now

**Goal:** Jafar can sell a reviews-only "Review Generation" package like Review Harvest. A business on it sees
only what asking for Google reviews needs, and the package builder lets Jafar untick the basics while it
automatically adds whatever a ticked feature needs.
**Plan:** `docs/review-generation-package-behavior-contract.md`

**In progress:** none

**Next part:** 1 Plan: unlocking the basics — research each of its questions, then ask Jafar in one round.

**Blockers:** none. Build parts that change the package builder wait for the package-builder campaign's P16
tour.

The basics are forced in three places: the builder screen (`normalize` in
`src/routes/jafar/(protected)/packages/[packageId]/+page.svelte`), the draft save
(`supabase/migrations/20260930200000_package_drafts.sql`), and package exceptions
(`supabase/migrations/20261001090000_package_changes_and_exceptions.sql`). `src/lib/server/access/effective.ts`
already ties each permission to its feature, basics included.

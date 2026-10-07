# Package basics unlock — now

**Goal:** Jafar can build smaller packages by unticking the basics a package does not need. The builder adds
whatever a ticked feature needs, and a business on such a package sees no trace of what it lacks. The reviews-only
Review Generation package itself is later work (`Memory/deferred/review-generation-package.md`).
**Plan:** `docs/package-basics-unlock-behavior-contract.md`

**In progress:** Part 3 — built, on `main`; waits for Jafar's answer on the browser proof, see `parts/3.md`

**Next part:** 3 The package decides what shows. Where a missing feature still shows today:
`docs/research/package-basics-unlock-2026-10-07.md`.

**Blockers:** none. Build parts that change the package builder wait for the package-builder campaign's P16
tour.

The basics are forced in three places: the builder screen (`normalize` in
`src/routes/jafar/(protected)/packages/[packageId]/+page.svelte`), the draft save
(`supabase/migrations/20260930200000_package_drafts.sql`), and package exceptions
(`supabase/migrations/20261001090000_package_changes_and_exceptions.sql`). `src/lib/server/access/effective.ts`
ties permissions to features, but `settings.*`, `time.*`, `expenses.*`, `field_records.*`, `files.*` belong to none.

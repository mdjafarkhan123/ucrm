# Part 5A: Staff publication and lifecycle

Approved 2026-08-21. Part 5's first subpart. It gives staff the controls that publish a version and record a
decision, and nothing customer-facing. Part 5B owns the customer link and page; Part 5C owns signatures.

## Approved behavior

- **Publish.** One command freezes the draft into the next published version and moves the Quote to
  `awaiting_response`, stamping `sent_at`. Publishing the same draft revision twice returns the version that
  already exists instead of publishing again.
- **Revise.** One command clones the current published version into a mutable draft and returns the Quote to
  `draft`. Refused when a draft already exists.
- **Offline decision.** One command records `approved` or `declined` with method `offline_verbal` and an
  optional note. Approving a quote that is still a draft publishes it first. No signature in this subpart.
- **Header.** Status-aware primary action; a `Mark as...` group listing only states the Quote is not already
  in; a facts row that grows Created -> Sent -> Approved/Declined; the version history affordance.
- **No email.** Jafar's call: Part 5 never sends email. Communications owns delivery. The primary action stays
  named `Mark as awaiting response` until Part 5B gives it a real customer link to hand over.

## Dependencies

Parts 3 and 4: `freeze_quote_version`, `clone_quote_version_to_draft`, the version-aware read, and the
draft-gated editing UI all exist. Both database functions are still unexecutable by `authenticated`; this
subpart is what gives staff a route that calls them.

## Checklist

- [x] Migration `20260821160000_quote_publication_and_decisions.sql`: six lifecycle columns on
      `public.quotes`, three check constraints, `quotes_decided_by_idx`, `quotes.send` and
      `quotes.record_decision` seeded for owner/admin/office/sales, and `publish_quote`, `revise_quote`,
      `record_quote_decision` granted to `authenticated` (freeze and clone stay closed).
- [x] `performance-review` on the migration. Two fixes came out of it: the line check named its quote so it
      uses `quote_version_lines_version_idx`, and `sent_at` is stamped before the freeze.
- [x] `supabase/tests/database/quote_publication_and_decisions.sql` - plan 50, all passing.
- [x] API routes `POST /api/quotes/[id]/publish|revise|decision`, each Zod-validated, each asking for its own
      permission, each calling `supabase.rpc(...)` as a method. The quote read now returns `sent_at`,
      `decision`, `decided_at`, `can_send`, and `can_record_decision`.
- [x] `performance-review` on the routes. 12 new route tests; suite at 778.
- [x] Header on `/quotes/[id]`: status-aware primary action, a `Mark as...` menu that lists no no-ops,
      the growing facts row, and the history panel (hover-prefetched, swaps the rail like Requests).
- [x] `performance-review` and `svelte-autofixer` on the component work.
- [x] Browser pass on Quote #33: rapid double-click published exactly Version 2; revision produced one
      editable draft; republish produced Version 3; approval stamped the facts row; history named both
      publications, the revision, and approval with the correct actor.

## Acceptance checks

- Publishing twice on one revision produces one version, not two, and no `40001`.
- A quote with no draft cannot publish; a quote with a draft cannot revise.
- Declining stamps `declined_at` and leaves the published version readable and read-only.
- A member without `quotes.send` is refused by the database, not only by the hidden button.
- The facts row and status chip agree with the database after every action.

## Non-discoverable risks

- Jobber has no equivalent of our published-version freeze, so its header carries no version row. Ours must.
- Pipeline stays untouched. Marking a Quote approved does not mark its Opportunity Won: that is Part 7.
- `declined` is ours, not Jobber's. It is a stored state in the contract and needs its own chip.
- Jobber's Send-as-Email composer could not be toured (unverified trial email), so nothing here copies it.

## Source pointers

- `docs/quote-behavior-contract.md` - Lifecycle table, Versions/edits/signatures, Staff permissions.
- `.claude/skills/jobber/jobber-03-quotes.md` §8.3 - the live tour this subpart was planned from.
- `supabase/migrations/20260820161041_quote_professional_proposals_foundation.sql` - freeze and clone.
- `src/lib/server/quotes/commands.ts` - the shape every command route follows.

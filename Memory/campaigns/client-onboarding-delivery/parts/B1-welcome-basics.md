# B1 Welcome + basics — part note

**Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §2 and §3.1 (first half). Storage decision:
`docs/adr/0005-client-setup-answers-draft-snapshot-accepted.md`.
**Built in:** worktree `.claude/worktrees/onboarding-b1`, branch `worktree-onboarding-b1` (claim
`eb4e084212bc`, owner `opus-onboarding-b1`). Waiting to merge until its code is on `main`. This note is
committed on that branch because the worktree session cannot write the main folder.

## Steps

- [x] ADR 0005 written (draft / submitted snapshot / accepted value)
- [x] Migration file `20261002203000_client_setup_draft_answers.sql` written
- [x] Server routes under `/api/setup`, catalogue in `src/lib/setup/catalogue.ts`, unit tests passing
- [x] Screens written: dashboard `SetupCard` (replaces `GettingStartedCard`), `/setup`, `/setup/business`
- [ ] Migration pushed to the remote database
- [ ] Browser check: fill half on desktop width, sign in again at phone width, continue; CRM menu works
- [ ] Merge branch into `main`, remove worktree, release claim

## Outside action

Pushing migration version `20261002203000` with `npx supabase db push --linked`. **Outcome check before any
retry:** the Supabase migration list shows version `20261002203000`, and table
`public.organization_setup_answers` exists. If both are true it already ran — do not push again.

## Next

Push the migration (after the outcome check above), then run the browser check as the contractor owner.

## Decided in this part

- Registration/tax number is not asked in B1: the plan asks it "only where a provider requires it", which
  only the package ticks (A2/B3) and texting facts (B9) can decide.
- The old getting-started checklist (price book, first client, invite team) is removed with its card; B11
  "CRM defaults" is where those nudges return.

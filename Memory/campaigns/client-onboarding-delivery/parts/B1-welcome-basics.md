# B1 Welcome + basics — part note

**Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §2 and §3.1 (first half). Storage decision:
`docs/adr/0005-client-setup-answers-draft-snapshot-accepted.md`.
**Built in:** worktree `.claude/worktrees/onboarding-b1`, branch `worktree-onboarding-b1`. Everything is
committed on that branch. **Waiting to merge** into `main`.

## Steps

- [x] ADR 0005 written (draft / submitted snapshot / accepted value)
- [x] Migration `20261002203000_client_setup_draft_answers.sql` written and pushed to the remote database
- [x] Server routes under `/api/setup`, catalogue in `src/lib/setup/catalogue.ts`, unit tests passing
- [x] Screens: dashboard `SetupCard` (replaces `GettingStartedCard`), `/setup`, `/setup/business`, new
      shared `ui/RadioGroup.svelte`
- [x] Browser check passed as the Raad LTD owner: welcome shown once, half filled at desktop width, signed in
      again at phone width and continued, CRM menu worked, marked done
- [ ] Merge branch into `main`, remove the worktree and branch, mark B1 done in the stage file

## Outside action — already done, do not repeat

Migration version `20261002203000` is applied (the Supabase migration list shows it; the three
`organization_setup*` tables exist). Raad LTD now has real setup answers and "Your business" marked done.

## Next

Merge `worktree-onboarding-b1` into `main`. It changes `src/lib/database.types.ts` (three tables and three
functions added by hand, nothing else), which the Pipeline C3 session also had uncommitted in the main
folder — merge after that session commits, or Git will refuse. Then run `npm run test:unit` for
`src/lib/setup` and `src/routes/api/setup`, remove the worktree, and finish the part.

## Decided in this part

- Registration/tax number is not asked in B1: the plan asks it "only where a provider requires it", which
  only the package ticks (A2/B3) and texting facts (B9) can decide. B9 owns it.
- The old getting-started checklist (price book, first client, invite team) is removed with its card; B11
  "CRM defaults" is where those nudges return.
- The welcome's "how to ask for help" line points at "I need Uplift's help"; D1 should add the chat to it.

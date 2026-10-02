# D4a — Chats + topics

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 4, § 7
**Code:** worktree `.claude/worktrees/onboarding-d4`, branch `worktree-onboarding-d4` (work-in-progress commit on it)
**Done when:** A member starts two chats with different topics; `/jafar` filter shows only the matching one

## Steps

- [x] Plan §4 and §7 updated on the branch (Jafar approved 2026-10-02)
- [x] Migration written: `supabase/migrations/20261003180000_support_chats_and_topics.sql` (renumbered: main's pipeline work took 120000)
- [x] Member API + messenger written: chat list, New message with topic chips, topic menu in header
- [x] `/jafar` inbox written: topic on rows, topic filter (`?topic=`), topic menu
- [x] Type check passes (0 errors, 2026-10-02)
- [x] Both support specs updated; 76 tests pass
- [ ] Apply migration, regenerate `src/lib/database.types.ts`, browser check both sides
- [ ] Merge branch into `main`, then mark D4a done

## Next

Main is merged into the branch. Apply the migration (`npx --no-install supabase db push --linked` from the
worktree), regenerate `src/lib/database.types.ts`, browser check both sides, then merge the branch into `main`.

## Outside actions

- Apply the migration from the worktree, only right before merging — the old code on `main` cannot start a
  new chat once it is applied. Check: `npx --no-install supabase migration list --linked` shows
  `20261003180000` — pending until pushed.

## Notes

Jafar's decisions 2026-10-02: Intercom model — each new question is its own chat; topic optional, starts
"Other"; topics Setup, Website, Google Profile, CRM, Billing, Other; changed by the starter, an owner/admin, or
Uplift, each change a grey line. Existing chats stay, topic Other. "Ask Uplift" (D6) will start a new chat
about that section. D4b attachments: photos + documents, 5 files / 20 MB per message, program files blocked;
reuse `communications/ConversationAttachments.svelte` and the `resolveOutboundAttachments` check pattern.

The tool sandbox refuses git in the main folder while a session is "entered" in a worktree: work from the
main folder and reach the worktree by full path instead.

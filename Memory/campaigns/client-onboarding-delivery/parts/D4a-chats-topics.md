# D4a — Chats + topics

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 4, § 7
**Code:** worktree `.claude/worktrees/onboarding-d4`, branch `worktree-onboarding-d4` (work-in-progress commit on it)
**Done when:** A member starts two chats with different topics; `/jafar` filter shows only the matching one

## Steps

- [x] Plan §4 and §7 updated on the branch (Jafar approved 2026-10-02)
- [x] Migration written: `supabase/migrations/20261003120000_support_chats_and_topics.sql` — NOT applied
- [x] Member API + messenger written: chat list, New message with topic chips, topic menu in header
- [x] `/jafar` inbox written: topic on rows, topic filter (`?topic=`), topic menu
- [ ] Type check passes (last run: one error, fixed but not re-run)
- [ ] Update `src/routes/api/support/support.spec.ts` and `src/routes/api/jafar/support/support.spec.ts` for the new routes (POST /api/support/threads starts a chat; messages need `thread_id`; PATCH topic)
- [ ] Apply migration, regenerate `src/lib/database.types.ts`, browser check both sides
- [ ] Merge branch into `main`, then mark D4a done

## Next

In the worktree, run `NODE_OPTIONS=--max-old-space-size=8192 npx svelte-check --threshold error` (plain
`npm run check` runs out of memory). Then fix the two spec files, then `npm run test:unit` on them.

## Outside actions

- Apply the migration with `supabase db push --linked` from the worktree, only right before merging — the old
  code on `main` cannot start a new chat once it is applied. Check: `supabase migration list --linked` shows
  `20261003120000` — pending.

## Notes

Jafar's decisions 2026-10-02: Intercom model — each new question is its own chat; topic optional, starts
"Other"; topics Setup, Website, Google Profile, CRM, Billing, Other; changed by the starter, an owner/admin, or
Uplift, each change a grey line. Existing chats stay, topic Other. "Ask Uplift" (D6) will start a new chat
about that section. D4b attachments: photos + documents, 5 files / 20 MB per message, program files blocked;
reuse `communications/ConversationAttachments.svelte` and the `resolveOutboundAttachments` check pattern.

The tool sandbox refuses git in the main folder while a session is "entered" in a worktree: work from the
main folder and reach the worktree by full path instead.

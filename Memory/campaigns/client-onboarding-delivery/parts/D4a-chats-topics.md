# D4a — Chats + topics

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 4, § 7
**Code:** worktree `.claude/worktrees/onboarding-d4`, branch `worktree-onboarding-d4`
**Done when:** A member starts two chats with different topics; `/jafar` filter shows only the matching one

## Steps

- [ ] Plan §4 and §7 updated: a new chat per question, topic per chat (Jafar approved 2026-10-02)
- [ ] Migration: topic column, several chats per member, start-a-chat and change-topic functions
- [ ] Member API + messenger: chat list (yours + team), New message with optional topic chips, topic chip in header
- [ ] `/jafar` inbox: topic on rows, topic filter, change topic
- [ ] Tests, checks, browser check both sides; merge to `main`

## Next

Write the plan edits in the worktree, then the migration `supabase/migrations/20261003120000_support_chats_and_topics.sql`.

## Notes

Jafar's decisions 2026-10-02: Intercom model — each new question is its own chat; topic optional, starts
"Other"; topics Setup, Website, Google Profile, CRM, Billing, Other; changed by the starter, an owner/admin, or
Uplift, each change a grey line. Existing chats stay, topic Other. "Ask Uplift" (D6) will start a new chat
about that section. D4b attachments: photos + documents, 5 files / 20 MB per message, program files blocked.

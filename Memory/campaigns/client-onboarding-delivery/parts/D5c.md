# D5c — Chat with Uplift on the paused screen

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 7
**Code:** `main`
**Done when:** A member of a paused business sends a message from the paused screen and sees the reply; nothing else opens

## Steps

- [x] Migration `supabase/migrations/20261006170000_support_while_paused.sql`: support-only member/admin checks that allow suspended and pending-closure businesses (not closed), `support_member_context()`, `support_teammate_names()`
- [ ] Apply the migration; regenerate `src/lib/database.types.ts`
- [ ] `requireSupportMember` (`src/lib/server/support/access.ts`) uses `support_member_context`; `teammateNames` uses `support_teammate_names`
- [ ] Show `SupportMessenger` on `PausedAccountScreen` (`src/routes/(app)/+layout.svelte`)
- [ ] Tests (support.spec.ts) + database check with a suspended test business; browser run

## Next

Apply the migration, then the server and layout changes above.

## Outside actions

- Apply migration — check: `list_migrations` shows version `20261006170000` — pending

## Notes

Every team member of a paused business gets the chat, not only owners (plan: every active member may contact
support). Closed businesses get none.

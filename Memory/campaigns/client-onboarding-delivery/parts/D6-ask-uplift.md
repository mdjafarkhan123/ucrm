# D6 Ask Uplift — part note

**Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §4 (last sentence) and §7 "screen/section context".
**Approach (Intercom/Zendesk "conversation started on page"):** a chat started from a setup section keeps that
section's key (`support_threads.context_section`); topic starts as Setup; the member's composer shows the attached
section (removable); Uplift's inbox and the chat header show "Asked from setup: <section>".

## Steps
- [ ] Migration `20261006190000_support_ask_from_setup.sql` applied to remote. Outcome check: Supabase
  `list_migrations` shows version 20261006190000, or `support_threads.context_section` exists.
- [ ] Zod + route + server reads return the section label
- [ ] Messenger: ask(context) via Svelte context from the app layout; setup section page button
- [ ] Jafar inbox header shows the section
- [ ] Tests, checks, browser run (owner on setup → Ask Uplift → Jafar sees section)

## Next
Apply the migration, then regenerate `src/lib/database.types.ts`.

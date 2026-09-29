# Part 9 — Chat identity (contact matching priority)

**Campaign:** deferred-sweep-2 · **Spec:** `Memory/deferred/resolving-a-chat-identity-does-not-stop-the-next-conflict.md` · **Plan doc:** `docs/website-chat-behavior-contract.md` (identity section)
**Code:** `main`
**Done when:** a visitor whose phone and email belong to two different clients is matched by the contractor's priority setting (chat and website forms), with no repeat "Needs review".

## Decisions (Jafar, 2026-09-29)

- "Follow GHL/Jobber". Chose: a contractor setting like HighLevel's Contact deduplication preferences —
  match **email first** (default) or **phone first**; the other identifier is the fallback. No client is edited.
- Merge clients = Jobber's answer for true duplicates; already built (`20260929170000_merge_clients.sql`).
- Same rule applies to website forms, which today create a contactless duplicate on a clash (found this session).

## Steps

- [x] Migration (`20260929220000_contact_match_priority.sql`): `organization_settings` column (email|phone, default email) + one private matcher used by
      `accept_website_chat_first_message` and `process_next_form_submission`
- [ ] Settings UI for the choice + API (Zod) ; update behavior contract identity paragraph
- [ ] Tests; old Needs review sessions stay resolvable by staff; browser check
- [ ] Close: delete deferred note + row, mark Done

## Outside actions

- Migration `20260929220000_contact_match_priority` pushed — check: `npx --no-install supabase migration list --linked`

## Next

If the push is not confirmed, check the outside action first. Then: API route `src/routes/api/settings/contact-matching/+server.ts`
(copy `api/settings/pipeline`), page `settings/contact-matching` (copy `settings/pipeline`, radio choice),
card in `settings/+page.svelte` Business section, regenerate `src/lib/database.types.ts`.

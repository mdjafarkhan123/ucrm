# Part 10 — Merge duplicate clients

**Campaign:** deferred-launch-sweep · **Plan:** `docs/client-property-behavior-contract.md` § Duplicate merge
**Code:** `main`
**Done when:** an owner/admin can merge one client into another from the Clients list More actions and the
client page `…` menu; everything moves, money untouched, the survivor's history records it, old links
redirect; browser-verified on Raad LTD.

## Steps

- [x] Research Jobber (help.getjobber.com/en/articles/merge-duplicate-clients) and ask Jafar
- [ ] Migration: `client_merges` record table, `client_merge_preview`, `merge_clients`, history triggers step
      aside while a merge runs (same pattern as `private.property_delete_in_progress` in `20260929140000`)
- [ ] Test the function in rolled-back transactions on the live DB, then push
- [ ] `/api/clients/merge` (preview GET + POST, Zod, `customers.merge`) and old-link redirect
- [ ] UI: merge dialog (pick other client, swap arrows, confirmation screen listing what moves + warnings)
      in Clients list More actions and client page `…`
- [ ] Browser-verify on Raad LTD, update contract + jobber-01 skill, close the deferred note

## Next

Migration written: `supabase/migrations/20260929170000_merge_clients.sql`. Push it, then run the rolled-back
test in the scratchpad (merge "Tester Account" into "Greenfield Property Group" on Raad LTD as the owner;
office role must be refused), then build the API.

## Outside actions

- Push migration `20260929170000` — check: `npx --no-install supabase migration list --linked` shows it
  remote — pending

## Notes

Jafar's decisions, 2026-09-28 (all the recommended options):
- Secondary client is deleted; a permanent merge record keeps its name/phones/emails, who and when; old links
  to it open the survivor.
- Everything moves, including invoices, payments and opening balances — only the client link changes;
  issued documents keep the name printed on them.
- Opt-outs: any "stop"/unsubscribe on either record survives. Otherwise primary wins; blanks fill from the
  secondary; phones, emails and tags combine with duplicates removed.
- Button in both places, like Jobber. No undo (Jobber has none).
- Refuse (Jobber's blockers): either client deleted, a card checkout open/processing for the secondary.
- Permission `customers.merge` already exists (owner + admin).

# A4 — Stage editor

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 2.1
**Code:** `main`
**Done when:** A stage tied to Website shows only to a client whose package includes Website

## Steps

- [x] Migration `20261007110000_setup_stage_editor` (draft/save/publish/discard, per-client service filter, onboarding list per-client totals) — applied to dev
- [x] Wizard filter (`readOrganizationSetupCatalogue`), reminders, support start, onboarding list per-client totals
- [x] Jafar API `/api/jafar/setup` (+ `/draft`, `/draft/publish`) and page `/jafar/setup` ("Client setup" in the menu)
- [x] Unit tests (full suite green), svelte-check clean, committed
- [x] Browser: start draft, add stage, limit to Premium website, reorder, save, publish review — all work
- [ ] Fix publish-review wording: `publishChanges` in `src/lib/jafar/setup-editor.ts` lowercases the service name ("only clients with premium website"); keep the name's own case, update `setup-editor.spec.ts`
- [ ] Browser: discard the test draft (version 2, stage "Website and domain") via the page's Discard draft button
- [ ] Close the part (see Next)

## Next

Fix the wording above, then discard the leftover test draft on `/jafar/setup`. The full done-check (a client
seeing a Website stage) needs a stage with a question, which arrives in A5 — do NOT publish a test stage on
dev (it would burn the `website…` stage key forever). Ask Jafar to accept A4 on: rules proven in SQL (rolled
back), filter unit-tested, editor browser-checked; final client-side proof moves into A5's done-check. Then mark
A4 done in `stages/A-groundwork.md`, point `NOW.md` at A5, delete this note.

## Notes

- Rules decided: a stage holding built-in questions can't be removed or tied to a service; a stage with no questions is saved but hidden from clients; new stage keys never reuse any version's key.
- No dev client currently has a package edition with `service_key` entries, so every client sees only "Your business" today.

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
- [x] Publish-review wording keeps the service name's own capitals (browser-checked)
- [x] Test draft (version 2) discarded via the page; only version 1 remains
- [ ] Close the part (see Next)

## Next

Waiting on Jafar's answer to: "Can A4 count as finished now, with the last proof — a real client seeing a
Website-only stage — checked at the end of A5, once stages can hold questions?" On yes: mark A4 done in
`stages/A-groundwork.md`, add that proof to A5's done-check, point `NOW.md` at A5, delete this note. Do NOT
publish a test stage on dev (it burns the `website…` stage key forever).

## Notes

- Rules decided: a stage holding built-in questions can't be removed or tied to a service; a stage with no questions is saved but hidden from clients; new stage keys never reuse any version's key.
- No dev client currently has a package edition with `service_key` entries, so every client sees only "Your business" today.

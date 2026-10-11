# Part 3 — Selected-loading proof

**Campaign:** selectable-design-experiences · **Plan:** `docs/selectable-design-experiences-behavior-contract.md` § Approved execution order
**Code:** `main`
**Done when:** Locally served release manifest/network proves no inactive exclusive assets, SSR shell/no wrong-design frame and isolated warming; mechanism recorded.

## Steps

- [x] Capture initial release baseline and Classic desktop/phone screenshots.
- [x] Build a gated synthetic shell/surface fixture and repeatable manifest/browser verifier.
- [x] Reject plain universal-load dynamic imports: SSR emits both designs' CSS links.
- [ ] Prove a revised mechanism with selected-only SSR CSS and browser imports.
- [ ] Capture cold signed-in baseline and matching post-change measurements before real shell migration.
- [ ] Record the proven mechanism in an ADR; close Part 3 only when the verifier passes.

## Next

Read `docs/research/selectable-design-loading-2026-10-11.md` for the experiment, source-level cause and exact repeat commands. Keep the current failing isolation assertion. Separate server rendering imports from browser-only surface imports, inspect the resulting manifest and establish selected SSR stylesheet delivery before migrating real components. Do not patch framework internals or filter HTML strings. The fixture remains localhost-only and explicitly enabled; app shell/root files are unchanged.

## Notes

The manifest has separate exclusive JS/CSS chunks, but SvelteKit gathers stylesheet links across dynamic server imports. Separate files alone are insufficient. Its preload callback does not suppress stylesheet links. Root Classic styles are still shared by this fixture, so even a future exclusive-asset pass does not establish full workspace isolation. No saved selection, organization behavior or rollout has been implemented.

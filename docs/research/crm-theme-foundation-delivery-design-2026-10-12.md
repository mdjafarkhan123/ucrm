# Theme foundation — delivery design

**Status:** Planning design; no implementation, schema or infrastructure changed. Product behavior and sequence were approved by Jafar on 2026-10-12 in the [foundation agreement](../crm-theme-foundation-behavior-contract.md). This supports the existing `crm-design-system` campaign.

## Feasibility and reuse

The [focused source check](crm-design-system-foundation-2026-10-11.md) establishes the explicit dynamic frame imports, shared shell, global styling and private preview. Reuse those seams; do not rebuild a shell or business page tree. Extend presentation support at shared layout/component boundaries, keeping queries, mutations, access resolution and business operations shared. Later Botanical layouts may supply different markup without separate business state machines.

Current settings precedents: `src/lib/settings/api.ts` describes independently versioned settings sections; `src/routes/api/settings/branding/+server.ts` validates through Zod, authorizes against the active organization, and handles stale saves. Reuse that approach for a bounded organization preference, with theme-specific owner/admin authority rather than assuming a broader editable-settings permission is identical. Database representation/RLS/migration design comes after behavior approval, with the Postgres skill; none is proposed here.

Current SvelteKit `beforeNavigate` supports cancellation, including leave warnings. [Official navigation documentation](https://svelte.dev/docs/kit/$app-navigation). Existing settings pages use it individually. `RecordDetailLayout.svelte` receives editing/dirty/saving signals; `RecordFormLayout.svelte` does not expose a shared dirty/saving signal. Existing guards do not establish a complete safe-switch contract.

## Module responsibilities

- A small explicit catalog owns valid design IDs, server-authoritative readiness and lazy presentation loaders. The public server accepts only released IDs; private synthetic IDs cannot be persisted through its API. Keep the existing Classic default for absent preferences; distinguish absence from failed reads or invalid values.
- A preference service owns authorized reads, version-checked writes and uncertain-outcome reconciliation. Expose it through `/api/*`; never let a browser-supplied organization ID establish authority. Recheck availability and membership at save time. Treat identical-target saves as harmless after authorization.
- A request-scoped SSR resolver supplies the fresh visit's selected design. A per-tab client coordinator pins the applied design separately from the latest organization preference. Route data updates/preloads must not implicitly replace it or load a pending design. Use Svelte context/component state, with no mutable server singleton or cookie pretending to be the organization's source of truth.
- A shared edit-safety registry aggregates open editors, dirty values, staged files and pending operations. Register/unregister with component lifetime. A route/overlay coverage inventory declares proven safe surfaces and their retained route/filter/tab/scroll state; unknown coverage blocks Apply. Prefer existing shared shells, then wire remaining bespoke surfaces in bounded batches. The coordinator cannot infer safety from DOM input values or treat a hidden modal as safe.
- TanStack Query owns fetched preference metadata. Use a tenant/session-scoped key and one observer per tab, with foreground checks, deduplication and bounded retries. An applied design is UI session state, not a competing server-state cache. A save invalidates affected preference/settings metadata, not all business-record queries. Clear scope on sign-out/account change.
- Prepare the requested frame/style scope before swapping. Keep drafts mounted, check safety before preparation and recheck immediately before replacement using a safety-generation token or equivalent. If safety changed, cancel replacement and retain the current workspace. Capture inventoried route/view state, scope exclusive styles so old styles cannot bleed through, and provide recovery without silently changing the saved choice. Fresh SSR failures use a recoverable error surface. Readiness of shared dialogs/portals and global token overrides is part of the delivery proof.

## Private proof and final live proof

Use a small synthetic presentation and isolated in-process selection repository in the integration harness, exercising the production selection/coordinator/validation logic. Inject test identities at the harness boundary while testing real authorization decisions; never turn a forged browser role into authorization. A fixture is not a public theme or a new deployable application. Ensure production startup cannot enable the harness or write fixture IDs into organization settings.

Stage A also requires real database-backed adapter and authorization tests against isolated test data: written preference/fresh read, revision conflicts, unauthorized/cross-organization attempts and retry semantics. Select the isolation/rollback/cleanup mechanism after approved schema design; a production catalog must never accept synthetic IDs or activate incomplete designs. Record actual database outcomes and cleanup. Harness tests alone cannot close the persistence part.

Check the running application's Classic chooser states, real role boundaries and private presentation behavior separately. This proves only the documented technical scope. The actual customer Classic↔Botanical save/apply journey on the completed themes and full visual coverage remain mandatory after Botanical is complete. Save evidence under the active campaign; do not label a mocked repository run as live persistence proof.

## Performance design verdict

**Growth path:** exclusive design/page assets grow as themes and covered routes grow; metadata checks grow with visible tabs; safety registrations grow with simultaneously mounted editors. Preference access itself is bounded to one active organization's small record.

**Workload:** initial catalog has two customer designs plus a test-only fixture; one active organization and one coordinator/observer per tab. No production concurrency target is approved. Proof uses two organizations, owner/admin/staff identities and four simultaneous tabs, including an offline/hidden tab. Preference checks occur at most once per 60 seconds per visible online tab, plus deduplicated focus/navigation checks. Steady-state timer load is at most V/60 requests per second for V such tabs, before event-triggered checks; event checks are coalesced with a five-second minimum interval. Organization saves are rare, version checked and bounded by existing security controls.

**Chosen shape:** reuse explicit selected-frame loading and SSR shell; one bounded settings preference; a small per-tab coordinator and safety registry; TanStack metadata query with foreground polling/focus/navigation. No server cache, queue, Redis service, new Realtime subscription, custom component framework or new dependency is justified for this proof. This bounds local work; it establishes no traffic capacity.

**Rejected alternatives:** broadcasting remounts loses drafts; a global browser/server theme singleton risks cross-scope state; eager imports deliver unused designs; a parallel preference cache complicates invalidation; a new event bus adds subscription/security cost before a faster notification requirement exists.

**Required verification:** release-build SSR and request graphs for both selected presentations; zero inactive exclusive design assets on ordinary cold loads, warming and navigation; explicit preview/apply loading separately identified; effective styles after repeated switching; one coalesced metadata request path with hidden/offline cleanup and sign-out cleanup; observed four-tab request counts and notice delay; editor registrations returning to baseline after closing/navigating; representative Classic payload/LCP/CLS comparison using the saved throttled workload. Record existing poor dashboard values separately; do not claim faster loading or fix unrelated dashboard work silently. Verification follows the performance skill's implementation branch once the coherent slice exists.

**Remaining proof:** Product behavior and sequence are approved; implementation has not been verified. Runtime isolation, shared-style separation, complete edit-safety coverage and request budgets are unverified until their parts run. Whole-theme/release evidence belongs to Stage B's release gate. Production traffic sizing remains unestablished.

**Overall:** Feasible for the bounded foundation proof; product behavior and sequence approved 2026-10-12. This feasibility verdict is not implementation completion or a production performance claim.

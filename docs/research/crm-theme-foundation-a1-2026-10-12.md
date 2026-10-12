# A1 — selected delivery proof

**Result:** A1's bounded delivery seam and source inventory are verified. This is private technical proof, not saved organization selection, draft-safe application, complete Botanical or customer rollout. Existing approvals remain unchanged: foundation/initial Botanical sequence, v3 reference `faeccae3`, sidebar variant 2 revision 2 `983dcecb`, header B revision 4 `c5c6ad89`.

## Delivered and reused

The real shared shell and explicit selected-frame imports remain in place, with no business workflow, public appearance or database change. A1 strengthens `verify-real-design-shell.mjs` to check transitive frame assets, subtracting the authoritative shared root/app layout graph. The script asserts that neither frame is eager in that graph. Shared Bits UI dialog, Svelte and close-icon chunks are shared functionality, not Botanical-exclusive payload; comparing only the two frame graphs would misclassify them.

The synthetic private fixture now tests selected CSR content and deferred overlay content as well as SSR frames. Its keyed, component-local workspace corrects the old cross-design navigation hazard: SvelteKit reuses the route component, so an `onMount`-only surface loader could otherwise retain the previous presentation. Intentional fixture navigation starts independent state without touching public preferences. Overlay content uses the existing Dialog wrapper and its own scoped injected styles because the portal sits outside the shell.

Screen review fixed enlarged-text overflow in the synthetic heading/controls. Failure testing also showed that a failed dynamic-import URL remains failed in the browser; retrying the same button was misleading. The fixture now retains the usable page, disables that failed example button, and offers an explicit **Reload to retry** link. The real application’s later Apply-loading recovery still belongs to A5; no draft protection is inferred from reloading this read-only fixture.

The [apply-safety and state inventory](crm-theme-foundation-a1-inventory-2026-10-12.md) enumerates all 73 Business Workspace page routes and layout-owned overlays, with [source pointers and hashes](crm-theme-foundation-a1-2026-10-12/source-inventory.json). It assigns A3 signals and bounded A4a/A4b batches. Its route/filter/tab/selection/scroll obligations preserve the approved no-loss behavior. No static inventory row grants runtime safe coverage; unknown coverage must block Apply.

## Runtime evidence

All screenshots and raw results are in [the evidence folder](crm-theme-foundation-a1-2026-10-12/). The app was a local adapter-node release build, Chromium, 1440×900 and 390×900. The synthetic ordinary-load run used 4× CPU slowdown, 150ms latency, 200,000 bytes/s download and 93,750 bytes/s upload. Scripted timings are individual local lab observations, with other verification work on this machine; they are not a speed comparison, field percentiles or capacity evidence.

- [Selected loading results](crm-theme-foundation-a1-2026-10-12/results.json): both shells and their selected injected CSS appear in SSR; page content remains CSR. Cold load, idle warmer, hover and same-design navigation show zero inactive exclusive JS/CSS/assets or styles. Selected overlay content stays deferred until focus/hover/open.
- Four intentional switches per scenario (16 total) retain the effective selected canvas/accent and scoped overlay content after both designs’ styles have been injected. Old modules/styles may remain downloaded; they do not change the tested selected surfaces. No browser/hydration errors or normal/enlarged-text document overflow were observed. Modal keyboard containment, Escape, focus return and visible focus passed.
- Four overlapping opposite-design SSR requests remain isolated, with no cookie set. Fixture contexts finish with no cookies, local/session storage or `/api/*` requests. A real nonloopback Host header returns 404 even when the local proof is enabled. [Default release-startup checks](crm-theme-foundation-a1-2026-10-12/gate-results.json) return 404 for both fixture designs without the opt-in.
- [Recovery results](crm-theme-foundation-a1-2026-10-12/failure-results.json): aborting selected page-content imports leaves the selected SSR shell with a clear reload instruction. Aborting overlay imports leaves the usable page and explicit reload recovery; the recovered example opens, Escape closes it and focus returns to its button. Both designs/widths passed.
- [Current real-shell results](crm-theme-foundation-a1-2026-10-12/real-shell/results.json): existing contractor owner and field-member accounts, both frames and widths; Dashboard → Clients, sidebar/drawer focus and dismissal, shared account/photo/search/notification controls and pinned create-form geometry passed. Field-member destinations match between presentations. Control Room stays Classic. No business record was saved. Real-shell source was unchanged by the synthetic fixture fixes; its final run used the same final release build.

Representative captures: [private Classic desktop](crm-theme-foundation-a1-2026-10-12/classic-1440-switched.png), [private Botanical phone](crm-theme-foundation-a1-2026-10-12/botanical-390-switched.png), [portalled example](crm-theme-foundation-a1-2026-10-12/botanical-390-botanical-overlay.png), [current real Classic](crm-theme-foundation-a1-2026-10-12/real-shell/classic-1440.png), [private real Botanical navigation](crm-theme-foundation-a1-2026-10-12/real-shell/botanical-390-navigation.png).

## Checks and reproduction

- `npx svelte-kit sync` then `npm run build`: pass. The first fresh-worktree build needed sync before the widget build could find generated types; no application fix was needed. Existing unrelated compiler/build warnings remain.
- Focused `svelte-check`: **0 errors, 0 warnings** for all proof Svelte components/loaders and the fixture route, using a temporary config extending the repo config and including generated ambient declarations. Full `npm run check` exhausted the default Node heap after roughly 157 seconds; whole-project type checking remains unverified. The previous shell checkpoint also recorded unresolved whole-project checks. This task does not fix that separate checker problem.
- Svelte MCP autofixer: all six changed/added Svelte components pass. SCSS was Sass-preprocessed for analysis to avoid raw-SCSS false positives.
- Targeted ESLint and Prettier, plus `git diff --check`: pass. The widget build's generated unrelated changes were restored.

```sh
npx svelte-kit sync
npm run build
# Three separate terminals, same final build:
DESIGN_LOADING_PROOF=1 HOST=127.0.0.1 PORT=4187 node --env-file=.env build/index.js
HOST=127.0.0.1 PORT=4188 node --env-file=.env build/index.js
DESIGN_SHELL_PREVIEW=botanical HOST=127.0.0.1 PORT=4189 node --env-file=.env build/index.js
# Evidence defaults to temporary folders unless PROOF_OUTPUT is set:
PROOF_ORIGIN=http://127.0.0.1:4187 node scripts/verify-selected-design-loading.mjs
PROOF_ORIGIN=http://127.0.0.1:4187 node scripts/verify-design-loading-recovery.mjs
CLASSIC_PROOF_ORIGIN=http://127.0.0.1:4188 BOTANICAL_PROOF_ORIGIN=http://127.0.0.1:4189 node scripts/verify-real-design-shell.mjs
```

The real-shell script reads the existing ignored `Login.md`; credentials/session cookies are kept out of artifacts. For the focused type check, extend `tsconfig.json` and include `src/app.d.ts`, `.svelte-kit/ambient.d.ts`, `.svelte-kit/non-ambient.d.ts`, `src/lib/design-loading-proof/**` and `src/routes/demo/design-loading/**`. Limit checking to that config; it does not substitute for a passing whole-project check.

## Performance verdict and limits

The approved [delivery design](crm-theme-foundation-delivery-design-2026-10-12.md) remains the approach: explicit selected loaders, shared behavior, component-scoped/injected CSS and no new dependency/cache/service. A1 exercises two synthetic designs, four independent overlapping SSR selections and one route family with optional portalled content. Browser work grows only with deliberately loaded presentation modules. The measured inactive-exclusive budget is zero for the tested ordinary/warming paths; repeated-switch checks cover effective styles rather than promising unloading.

The real Business Workspace still shares page/control CSS and baseline fonts; actual Botanical page/overlay migrations must prove their own selected-only graphs. No independent Botanical font, dark palette, saved preference, polling, safety registry, route-state restoration or schema is implemented by A1. Database/role/conflict proof remains A2b; safety integrations A3/A4; notice/application A5; personal modes A6; consolidated checks A7; complete Botanical and real customer activation Stage B.

Current real Classic was screened in light/dark; Botanical dark remains unapproved. Existing narrow/enlarged-text create-form content clipping and the saved dashboard LCP/CLS findings remain unresolved, as in the October 11 evidence. They do not originate in this private fixture slice; do not claim whole-workspace accessibility, faster Dashboard, zero theme overhead or production capacity. Later affected page deliveries and release checks own those gaps. No infrastructure or production deployment occurred.

# Selected design loading — first release-build experiment

**Result: rejected mechanism, not a completed loading proof.** Explicit dynamic imports from a universal
load correctly select the rendered shell, but this installed SvelteKit build eagerly links both designs'
CSS. Do not migrate the real shell using this mechanism alone. Classic app files are unchanged.

## Scope and method

Baseline source: `965d55b8fc3a9a7a063158bcc207c35f92735ec3`. Installed stack: SvelteKit 2.70.2,
Svelte 5.56.8, Vite 8.2.0, adapter-node. Both `npm run build` runs succeeded. Files were served locally with
adapter-node over HTTP, without a production proxy. Chromium used 1440×900 and 390×900 viewports, 4× CPU
throttling, 150ms latency, 200,000 bytes/s download and 93,750 bytes/s upload. One browser session at a time.
These are lab observations, not field percentiles or traffic capacity evidence.

The synthetic fixture lives at `/demo/design-loading/{classic|botanical}/{overview|details}`. It requires
`DESIGN_LOADING_PROOF=1` and a localhost/127.0.0.1 hostname; otherwise it returns 404. It reads no business
records, exposes no saved selector, and does not replace any app layout. The page labels itself as a delivery
experiment, not an approved design. Existing root Classic CSS/toasts remain present and are deliberately
outside this experiment's exclusive asset sets. Whole-workspace isolation is not established.

The server validates a synthetic design identifier. Universal load awaits only its shell constructor;
the shared page loads only the selected surface on mount. The existing `warmPagesWhenIdle` helper warms
the details route; its link also exercises hover data preloading and client navigation. Each design has
separate shell and surface modules with local SCSS. Both presentations deliberately share simple fixture
structure to isolate delivery; this does not prove an approved redesigned shell or real workflow parity.

The manifest check traverses static dependencies for each presentation and subtracts shared files. Browser
checks record requests through initial load, idle warm, hover and navigation; inspect SSR HTML, hydration
errors, selected DOM identity, focus outline and document overflow. Unknown design and disabled preview
both returned 404. No permissions or tenant-selection behavior changed.

## Baseline

[Raw baseline](selectable-design-loading-2026-10-11/baseline.json) records login and subsequent signed-in
Classic dashboard assets, including idle warming. Baseline screenshots:
[desktop](selectable-design-loading-2026-10-11/baseline-classic-1440.png) and
[phone](selectable-design-loading-2026-10-11/baseline-classic-390.png).

Cold login: 25 JS/CSS/font resource entries, 140,689 encoded body bytes at both widths; LCP 492ms desktop,
476ms phone; CLS 0.000077 desktop, 0 phone. After login and 15 seconds settling/warming, cumulative entries
were 242, with 534,937 encoded bytes desktop and 512,268 phone. These cumulative totals include the login;
cache timing makes them unsuitable as a new isolated dashboard byte budget. A cold authenticated dashboard
load and post-change matching baseline still need capture before real shell migration. Baseline navigation
latency was not recorded. Do not compare this complete app journey with the tiny synthetic fixture as a
speed improvement.

## Experiment results

| Presentation | Width | LCP | CLS | Warm details click-to-heading |
| --- | --- | --- | --- | --- |
| Classic fixture | 1440 | 444ms | 0.00365 | 54ms |
| Classic fixture | 390 | 424ms | 0.07636 | 56ms |
| Botanical fixture | 1440 | 432ms | 0.00365 | 59ms |
| Botanical fixture | 390 | 424ms | 0.02474 | 57ms |

All four scenarios made 33 requests through navigation. The raw results contain per-asset encoded/transfer
bytes and request snapshots before hover and navigation. They show **two inactive exclusive CSS files per
scenario**, already linked in SSR HTML: the other shell and surface stylesheets. No inactive exclusive JS
request was observed. Selected shell markup was present in SSR; the surface was absent until hydration.
No hydration/page errors or wrong-design DOM identity was observed. Frame captures are samples, not proof
that every composited frame was inspected. Keyboard focus was visible and neither width overflowed.

[Raw request/manifest evidence](selectable-design-loading-2026-10-11/results.json). Synthetic captures use
`{design}-{width}[-first].png` in that folder. Both layouts were visually inspected at both widths, including
the loading capture. They are plain diagnostic surfaces, not premium shell previews. Empty/business-error,
role differences, dark appearance and 200% text resizing are not established by this experiment. No design
approval or rollout readiness follows from these captures.

## Cause and next investigation

Vite documents asynchronous CSS splitting, but that alone does not guarantee SvelteKit's SSR links are
selected-only. Its installed `src/exports/vite/build/build_server.js` calls `find_deps(..., true)` for route
component and universal modules and gathers eager CSS across dynamic imports also found in the server
manifest. `build/utils.js` traverses those imports. `runtime/server/page/render.js` then emits stylesheet
links for the union. `resolve({ preload })` can suppress resource hints, but the stylesheet link is still
emitted, so that callback alone cannot fix this.

Primary framework references: [SvelteKit universal/server load](https://svelte.dev/docs/kit/load#Universal-vs-server)
and [Vite CSS splitting](https://vite.dev/config/build-options.html#build-csscodesplit). Local source inspection
explains the observed behavior for the installed versions; the earlier architecture audit's candidate was
explicitly conditional on this experiment.

Next: investigate a presentation entry mechanism that supplies only the selected shell's SSR CSS and keeps
client imports/hover/idle graphs isolated. First separate server rendering imports from browser-only surface
imports and inspect the resulting manifest. If explicit asset entries are necessary, generate their mapping
from the build rather than hard-coding hashed filenames. Verify both SSR HTML and client navigation before
adopting it. Do not patch framework internals, disable SSR/preloading globally, duplicate routes, or filter
HTML strings as a shortcut. No ADR declaring a proven mechanism has been written.

## Repeat

```sh
npm run build
DESIGN_LOADING_PROOF=1 HOST=127.0.0.1 PORT=4175 node --env-file=.env build/index.js
# In another terminal:
node scripts/verify-selected-design-loading.mjs
```

The verifier saves all measurements and screenshots under `/tmp/selected-design-proof`, then exits nonzero
if inactive assets are found. Its current failing isolation assertion is intentional evidence of a rejected
approach. It is opt-in and is not added to ordinary application test commands. Authentication credentials
and environment secrets are absent from the saved evidence.

**Performance verdict:** initial-render correctness supported for this fixture; delivery isolation fails.
Full offered-workspace assets, real shell interactions and production delivery remain unverified and owned
by the remaining campaign parts. Capacity was not established.

Validation: release build and targeted Prettier checks passed. Svelte MCP autofixer reported no remaining
issues in all five fixture components (initial SCSS nesting warnings were resolved with explicit BEM
selectors). `npm run check` and a direct `svelte-check` attempt produced no diagnostics or completion in
this environment and were stopped; a full type-check pass is unverified. The isolation verifier completed
all four browser scenarios, saved evidence, and correctly exited nonzero for the twelve recorded SSR/request
violations. This checkpoint is unfinished proof work, not a completion claim.

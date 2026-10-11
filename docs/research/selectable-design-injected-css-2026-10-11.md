# Selected design loading — injected component CSS

The revised private fixture passes selected-only exclusive asset delivery for Classic and Botanical at
1440×900 and 390×900, including SSR, hydration, idle warming, hover and client navigation. The real app
shell and global Classic styles are unchanged. This completes the synthetic mechanism proof, not customer
rollout or full workspace isolation. The [first experiment](selectable-design-loading-2026-10-11.md)
remains recorded as rejected.

## Design and verified method

The growth risk is downloading every presentation as designs and their dependencies grow. This bounded
experiment has two designs, one shell and one surface per design, two routes and one browser session.
Its delivery budget is zero inactive exclusive JS, CSS or assets; the selected shell and its styles must
be present before hydration, with page content still CSR. No business-data query or cache changes apply.

[Svelte's documented component option](https://svelte.dev/docs/svelte/svelte-options) provides
`css="injected"`: rendered server components contribute head styles; browser components carry CSS in
JavaScript. Use it on the four exclusive fixture components, preserving explicit selected imports and
ordinary SvelteKit universal load. It avoids a separate SSR/client implementation, manual build asset
maps and framework changes. Component-local SCSS remains the source. Cost: shell styles appear in both
SSR HTML and its cached JS; CSR surface styles wait for JS. Large real design graphs require measurement.

The verifier retains manifest graph subtraction and rejects inactive requests and SSR asset links. It
also extracts injected style identities from built exclusive entries, requires the selected shell style
in SSR, excludes the CSR surface and inactive styles there, and checks selected-only style tags before
warming and after navigation. Missing compiled identities fail closed. This intentionally depends on the
installed compiler output shape and should be revisited after compiler upgrades. No hashed filenames are
hard-coded. DOM observation rejects wrong design identity and browser/hydration errors fail the run.

## Evidence

[Raw manifest, request and metric evidence](selectable-design-loading-2026-10-11/injected-css/results.json)
includes all four scenarios. Screenshots alongside it use `{design}-{width}[-first].png`. Both presentations'
loading and populated views were visually inspected at both widths: wrapping stays readable, navigation is
reachable, and no overflow or new visual defect was found. The diagnostic fixture deliberately remains
plain; these are not approved Botanical shell screenshots. Keyboard focus and the overview → details
journey passed. No business role, empty record or permission differences exist in this synthetic surface.

The profile is Chromium, 4× CPU, 150ms latency, 200,000 bytes/s down, 93,750 bytes/s up, local adapter-node
HTTP, one fresh context per scenario. These are single-run lab observations, not field percentiles.
Both designs made 29 requests through navigation, versus 33 in the rejected fixture. Zero inactive
exclusive requests or inline styles were observed. Consult raw evidence for the final run's timings.
Frame screenshots are samples; the DOM observer does not inspect every composited frame.

## Cold authenticated Classic baseline

The new `scripts/capture-classic-design-baseline.mjs` signs in through the real login using Login.md, then
opens `/dashboard` in a fresh browser context at each width. Storage state stays in memory; artifacts
contain asset paths and metrics, with no credentials or cookies. It waits 15 seconds for idle warming.
[Raw baseline](selectable-design-loading-2026-10-11/cold-authenticated-baseline.json),
[desktop](selectable-design-loading-2026-10-11/cold-classic-1440.png),
[phone](selectable-design-loading-2026-10-11/cold-classic-390.png).

| Width | Asset entries | Encoded bytes | LCP | CLS |
| --- | --- | --- | --- | --- |
| 1440 | 244 | 537,015 | 6,492ms | 0.09467 |
| 390 | 244 | 513,011 | 6,084ms | 0.21151 |

No page errors occurred. These cold authenticated values replace the earlier login-inclusive journey
as the comparison method for the coming real-shell slice. The app has not changed presentation yet, so
there is no migrated-shell comparison to report. Cold dashboard LCP and phone CLS miss the skill's good
thresholds; retain this existing regression budget and investigate during real-shell performance work.
Do not compare the tiny fixture with the dashboard as a speed improvement.

## Repeat and limits

```sh
npm run build
DESIGN_LOADING_PROOF=1 HOST=127.0.0.1 PORT=4175 node --env-file=.env build/index.js
# Separate terminal:
node scripts/verify-selected-design-loading.mjs
node scripts/capture-classic-design-baseline.mjs
```

Build passed. All four components passed Svelte MCP autofixer with no issues or suggestions. The browser
proof and authenticated baseline passed. Targeted Prettier checks passed. `npm run check` stalled without
diagnostics both inside and outside the sandbox; full type checking remains unverified. No database,
permissions, organization settings, production deployment or infrastructure was changed.

Performance verdict: supported selected-only fixture delivery; full real-shell dependency isolation,
shared base/token separation, CSP under production policy, dark appearance, real workflow parity,
200% text resizing and production proxy/compression/cache remain unverified. Part 4 owns the real shell
and matching baseline rerun; later coverage/release parts own full workspace and production evidence.
Capacity was not established. See [the scoped decision](../adr/0009-selected-presentation-component-css.md).

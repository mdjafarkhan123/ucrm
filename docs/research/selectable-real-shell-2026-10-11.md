# Selectable designs — real shared shell

The approved Botanical sidebar and header now run over the real Business Workspace shell in a private,
localhost-only preview. Classic remains the default, including the public tunnel and Control Room. This
is shell implementation evidence, not complete Botanical page coverage or release approval.

## Shape and design verdict

The workload is two presentations, one authenticated browser session, the existing bounded navigation
configuration and the unchanged daily-route warm list. The growth risk is delivering every design's
exclusive browser dependencies as presentations grow. The budget is zero inactive frame bundles or
injected frame styles, with the selected shell and its CSS present in SSR before hydration.

The verified [Svelte component CSS method](selectable-design-injected-css-2026-10-11.md) is retained:
universal layout load awaits one explicit dynamic frame import, and exclusive frames/navigation inject
their component-local SCSS. `SharedAppShell` owns permissions, account actions, search, notifications
and dialog state once. Both sidebars use one icon registry and active-route matcher. Classic's existing
caller remains a thin wrapper for Control Room; no business logic, database queries or route warming
is duplicated. Botanical uses installed Bits UI Dialog for the phone drawer's focus and dismissal.

The private selection requires both `DESIGN_SHELL_PREVIEW=botanical` and a localhost/127.0.0.1 request.
It does not save any organization preference. Import failures use normal SvelteKit error handling;
there is no silent Classic fallback. No dependency, cache, provider, migration or infrastructure was added.

Verification covers SSR, hydration, exclusive frame delivery, idle/hover warming, navigation, shared
controls, permissions, pinned action geometry and the same cold authenticated Classic workload. No
traffic capacity claim is made. Full workspace asset isolation, token/base-style separation and
production CSP/compression/cache remain later coverage/release work: existing page/control CSS still
belongs to the shared app graph, and these pages have not been redesigned.

## Browser evidence

[Raw results](selectable-real-shell-2026-10-11/results.json) and screenshots in the same directory record
Chromium at 1440×900 and 390×900, existing owner and field-member logins, and the locally served Node
release build. Test credentials and cookies are kept in memory, outside artifacts. The run was repeated on
the final code after a fresh release build; the Control Room check signs in as the test-only Uplift teammate
because Jafar's own Control Room password in `Login.md` is out of date.

- Both selected frames and injected styles were present in SSR. No inactive frame entry or injected
  style identity appeared in SSR or requests through idle warming, hover, client navigation and forms.
- Dashboard → Clients, desktop collapse/expand, phone menu link navigation, Tab containment, Escape
  and focus return passed. No wrong-presentation DOM or browser/hydration errors were observed.
- Account/security menu, profile-photo dialog, Ctrl+K search and notification panel opened successfully.
  Classic dark screenshots were checked; Botanical's existing personal appearance button remains
  reachable on phones. Botanical dark appearance remains unapproved and is not claimed as supported.
- Owner and field-member navigation destinations/labels match between presentations. Control Room
  stays Classic on the Botanical-preview server, including its phone menu.
- The pinned create-form Save/Cancel bar stays on screen and follows sidebar collapse. Its shared
  component and page's existing save behavior are retained; no business records were saved by this proof.
- Screen review corrected enlarged-text sidebar icon clipping, phone bar insets and enlarged-text
  header crowding. Long business names wrap; navigation scrolls independently of its collapse control.
  Existing Classic form content clips at phone/enlarged-text sizes; that page coverage is unfinished,
  and this private experiment does not approve it as Botanical. No outdoor/assistive-technology claim.

Account notices keep the existing slot between header and scrolling content. Grace/paused account
variants and shared-control failure states were inspected in code but not exercised with real accounts
in this proof. Later release verification must cover those states, draft/save journeys and sign-out.

## Cold Classic comparison

Same Chromium profile as the saved baseline: 4× CPU, 150ms latency, 200,000 bytes/s download,
93,750 bytes/s upload, fresh authenticated context per width, 15 seconds idle warming, local HTTP.
The comparison ran after competing build/check/browser work stopped. Values are individual lab runs,
not field percentiles or proof of a speed improvement.

| Width | Before/after asset entries | Before/after encoded bytes | Before/after LCP | Before/after CLS |
| --- | --- | --- | --- | --- |
| 1440 | 244 / 244 | 537,015 / 539,093 | 6,492 / 6,828ms | 0.09467 / 0.03965 |
| 390 | 244 / 244 | 513,011 / 515,095 | 6,084 / 6,472ms | 0.21151 / 0.20830 |

The split adds about 2.1KB encoded across the existing warm workload. LCP is slightly later in these
runs and still poor; phone CLS remains above 0.1. [Diagnostic baseline](selectable-real-shell-2026-10-11/classic-baseline.json)
identifies the setup-card status as LCP and the main shift when the asynchronously loaded setup card
pushes the stats section down. `SetupCard.svelte` renders no reserved card while its summary is absent.
This is a pre-existing dashboard loading issue, not demonstrated shell-induced movement. The dashboard
coverage part should design its loading reservation and investigate the request timing before claiming
faster loading. No dashboard behavior or query timing was changed here.

## Reproduce and checks

```sh
npm run build
# In separate terminals; same built app, no second checkout:
HOST=127.0.0.1 PORT=4175 node --env-file=.env build/index.js
DESIGN_SHELL_PREVIEW=botanical HOST=127.0.0.1 PORT=4176 node --env-file=.env build/index.js
# Browser verification (evidence lands in /tmp/real-design-shell unless PROOF_OUTPUT is set):
PROOF_OUTPUT=docs/research/selectable-real-shell-2026-10-11 node scripts/verify-real-design-shell.mjs
node scripts/capture-classic-design-baseline.mjs
```

Release build, targeted ESLint, targeted Prettier and Svelte MCP validation passed. For SCSS components,
the MCP received Sass-preprocessed styles to avoid raw-SCSS false positives. Existing MobileNav focus
and layout navigation-timer suggestions were reviewed and retained: they are DOM/timer effects, not
computable derived state. `npm run check` and direct svelte-check stalled without diagnostics for several
minutes and were stopped; full type checking remains unverified, as in the previous checkpoint.

Verdict: real shell delivery and the exercised journeys are supported; full workspace release,
Botanical dark coverage, the listed state matrix and existing dashboard performance are not established.
The selectable-design coverage/release parts own those remaining checks. No production deployment occurred.

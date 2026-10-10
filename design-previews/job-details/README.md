# Job details approval demo

Standalone HTML/SCSS preview using the approved balanced-type concept. Run from the repo root:

```sh
python3 -m http.server 4187 --bind 127.0.0.1 --directory design-previews/job-details
```

Open **http://localhost:4187**. The scenario selector covers populated and empty one-off jobs, loading, errors, editing, closed jobs, recurring per-visit and per-period pricing, as-needed scheduling, restricted staff, the final visit, changed signatures/reports, and long content.

Controls preview the corresponding editor, menu, confirmation, or destination. Title, instructions, notes and file changes demonstrate staging behind the pinned Save changes bar. Section editors carry their own sample save. Editors include a demo save-outcome selector to inspect failure without losing the draft. Reload resets the sample; switching scenarios restores that scene’s starting data. No API writes, messages, invoices, payments, signatures, uploads, real downloads or report links are produced. Editors demonstrate their fields and states rather than implementing the real app’s business engine. The sample photo illustrations are local SVGs, labelled as illustrations.

[Coverage and research](coverage.md) maps the current application to the demo and records what was checked. Dark design and destination pages require separate approval.

## Maintain and verify

```sh
npx sass design-previews/job-details/style.scss design-previews/job-details/style.css --no-source-map
npx prettier --write design-previews/job-details/style.css
node design-previews/job-details/verify.cjs
npx prettier --check design-previews/job-details/index.html design-previews/job-details/demo.js design-previews/job-details/style.scss design-previews/job-details/style.css design-previews/job-details/verify.cjs
```

The browser check uses the installed Playwright package, checks 13 scenarios at 1440px and 390px, opens 40 page actions at each width, checks temporary title saving/reset, mobile navigation and dialog dismissal, and writes screenshots to `/tmp/job-*.png`. It also fails on document overflow or browser script errors.

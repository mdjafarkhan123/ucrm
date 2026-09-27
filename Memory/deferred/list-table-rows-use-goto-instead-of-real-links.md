# List-table rows use goto() instead of real links

Row clicks and "View" menu items in most list pages (e.g. `clients/+page.svelte`, `invoices/+page.svelte`,
`quotes/+page.svelte`, `reviews/+page.svelte`) navigate via `goto()` rather than an `<a href>`. The
destination page's code is already warmed through the shell's `preloadCode` list, but that specific record's
data can't be prefetched on hover the way a real link would allow.

Deferred 2026-09-27: fixing it means adding `href` support to the shared table row / dropdown-menu components
used across most list pages — a wider-blast-radius change for a small win (data still loads almost instantly
on click today, just not pre-warmed on hover).

**Reactivation trigger:** list-to-detail navigation is reported as feeling slow, or the shared table/menu
components are being touched for another reason anyway.

**Known constraint:** the shared row/menu components currently only expose an `onSelect`/`onRowActivate`
callback, not an `href` prop — this needs to be added at that shared-component level, not per-page.

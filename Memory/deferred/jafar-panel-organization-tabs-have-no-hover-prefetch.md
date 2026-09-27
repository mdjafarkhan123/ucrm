# Jafar Panel organization tabs have no hover-prefetch

The contractor client detail page (`clients/[id=uuid]/+page.svelte`) prefetches a tab's data on hover before
the click, so switching tabs is instant. The Jafar Panel's organization detail page
(`src/routes/jafar/(protected)/organizations/[organizationId]/+page.svelte`, tabs: overview, access,
communications, team, activity) has no equivalent — every tab switch shows a loading skeleton.

Deferred 2026-09-27: Jafar's own internal tool, far lower traffic than contractor-facing pages; the loading
flash costs nothing real today.

**Reactivation trigger:** Jafar finds the tab-switch delay annoying in daily use, or the Jafar Panel gets
meaningfully more concurrent staff usage.

**Known constraint:** the fix is mechanical — copy the `Tabs.onhover` prefetch pattern already proven on the
contractor client page.

# Tab selection is read from a `page.url` that `replaceState` does not update

- **Priority:** P2
- **Why postponed:** Found while verifying Google review Part 5B. The Reviews page kept its open tab in the
  address bar and read it back from `page.url`; clicking "Private feedback" rewrote the address with
  `replaceState`, `page.url` did not follow, so `activeTab` stayed on the first tab and the panel rendered
  empty while the tab strip showed as selected. Opening the same address directly worked, which hid it.
  Proved with a temporary `$effect` probe: after the click the address bar read `?tab=feedback` while
  `page.url.search` was still `''`. Fixed on the Reviews page only (`74af3495`) by moving the open tab into
  page state; the same pattern is still in `clients/[id=uuid]` (masked — its hover prefetch fills the cache,
  so the panel looks right even while `active` is false), `marketing`, `marketing/campaigns/[id=uuid]`,
  `jafar/(protected)/{prospects,operations,organizations/[organizationId]}`,
  `settings/automation/RecipeDetailView.svelte` and `marketing/CampaignJourney.svelte`.
- **Reactivate when:** Any of those pages is worked on, a panel is reported blank or stale after a tab or
  filter click, or someone standardises tab-in-the-URL handling across the app.
- **Constraint:** The address bar and Back must keep working, so keep `replaceState`; only the source of
  truth moves. Each page also gates a query on the tab, so a wrong `activeTab` silently disables a fetch
  rather than erroring — grep for `replaceState` and check what reads `page.url` beside it.

The three Settings pages (Business Profile, Branding, Business Hours) each cleared `saving`/dirty state
and cached `saved = {...form}` before their `await queryClient.invalidateQueries(...)` had actually
refetched, so `query.data`'s revision could still be stale. An edit made immediately after a successful
save reused that stale `expected_revision` and got a false "someone else changed this" 409. Fixed
2026-08-24 by patching the revision into the query cache synchronously via `queryClient.setQueryData`
right after each successful save, ahead of the invalidate (see `src/routes/(app)/settings/business-profile/
+page.svelte`, `branding/+page.svelte`, `business-hours/+page.svelte`).

**Reactivation trigger:** when Part 3C's Team member detail page (`src/routes/(app)/settings/team/[userId]/
+page.svelte`, `update_team_member_profile` with `profile_revision`) is next touched, check whether its
save flow has the identical shape (revision read from `query.data` after invalidate rather than from the
save response) and apply the same synchronous-patch fix if so.

Priority: P2 — narrow race (only matters if a manager edits again within the invalidate/refetch window),
not user-facing today since nobody has hit it yet, but the same bug class already surfaced once.

# Data / Cache Architecture

## Goal

Establish safe, predictable TanStack Query ownership for the SvelteKit application before adding broader cache and realtime behavior.

## Audit findings

- The root layout imports one module-level `QueryClient` from `src/lib/query-client.ts`.
- The root layout can render on the server, so this client can retain data across requests.
- Mutating pages import that same module-level client directly instead of using the provider context.
- Existing query keys are ad hoc but already use domain prefixes such as `crm` and `jafar`.
- No SSR dehydration/hydration or Supabase Realtime cache bridge exists yet.

## Parts

1. [x] Scope the QueryClient per app instance/request and route all invalidation through the provider context.
2. [ ] Define shared query-key conventions for the existing domains.
3. [ ] Add the smallest safe hydration/cached-navigation improvement.
4. [ ] Add targeted invalidation and realtime integration after the query ownership is stable.

## Decisions

- Work one part per session.
- Do not add realtime or schema changes until query ownership is safe and verified.

## Files changed

- Session setup: `Memory/data-cache-architecture.md` created.
- 2026-08-12: `src/lib/query-client.ts` — replaced the module-level `export const queryClient` singleton
  with `export function createQueryClient()`, so a fresh instance is made per app/request instead of being
  shared across every visitor via the server module cache.
- 2026-08-12: `src/routes/+layout.svelte` — calls `createQueryClient()` inside the component script and
  passes that instance to `QueryClientProvider`, instead of importing the old shared singleton.
- 2026-08-12: `src/routes/(app)/dashboard/+page.svelte`, `src/routes/jafar/(protected)/prospects/+page.svelte`,
  `src/routes/jafar/(protected)/packages/+page.svelte`,
  `src/routes/jafar/(protected)/organizations/[organizationId]/+page.svelte` — replaced the direct
  `import { queryClient } from '$lib/query-client'` with `useQueryClient()` from `@tanstack/svelte-query`,
  which reads the client from the provider's Svelte context instead of a global import.
- Verified with `npm run check` — 0 errors (2 pre-existing unrelated CSS warnings on the dashboard page).

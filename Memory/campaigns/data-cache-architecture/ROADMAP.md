# Data and Cache Architecture Roadmap

| Part | Outcome | Status | Dependencies | Packet | Completion gate |
| --- | --- | --- | --- | --- | --- |
| 1 | Scope QueryClient per app/request and use provider context | Complete | None | Git history | Server requests cannot share one module-level cache. |
| 2 | Define shared query-key conventions for existing domains | Paused, next | 1 | `Memory/campaigns/data-cache-architecture/parts/02-query-key-conventions.md` | Every current query and invalidation maps to a stable documented key family. |
| 3 | Add the smallest safe hydration and cached-navigation improvement | Pending | 2 | Create when active | Shell SSR remains immediate and navigation uses safe cached data while revalidating. |
| 4 | Add targeted invalidation and justified Realtime integration | Pending | 2, 3, relevant domain behavior | Create when active | External changes update only affected caches without leaking tenant data or creating refetch storms. |

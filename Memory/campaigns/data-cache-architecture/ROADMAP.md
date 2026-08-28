# Data and Cache Architecture Roadmap

| Part | Outcome | State | Depends on | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Per-app QueryClient ownership | Closed | — | Server requests cannot share cache state |
| 2 | Shared query-key conventions | Paused, next | 1 | Existing queries and invalidations map to stable key families |
| 3 | Safe hydration and cached navigation | Pending | 2 | Shell stays immediate while cached data revalidates |
| 4 | Targeted invalidation and justified Realtime | Pending | 2–3 | External changes update only affected tenant-safe caches |

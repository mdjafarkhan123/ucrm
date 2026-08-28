# Pipeline navigation is visible without Pipeline access

- **Priority:** P1
- **Why postponed:** The shell lacks a cheap access context; resolving full access in layout would slow every page. The Pipeline route itself denies honestly without leaking data.
- **Reactivate when:** The access resolver is cached or the shell gains per-feature access context.
- **Constraint:** Gate all feature navigation through one shared access model, not Pipeline alone.
- **Pointers:** AppShell.svelte, (app)/+layout.server.ts, and the Pipeline page.

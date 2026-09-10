# App shell idle warmer downloads every routine route

- **Priority:** P2
- **Why postponed:** This is shared app-shell behavior, not a Jobs-owned blocker, and no bandwidth/device budget is
  approved.
- **Reactivate when:** Mobile/slow-network performance is reviewed, the warm-route list grows, or route delivery is
  redesigned.
- **Measured evidence:** Warming 35 routes added about 610.1 KB gzip beyond the shell and left 95 stylesheets in the
  measured production-preview browser; it runs after idle, outside the initial critical path.
- **Constraint:** Keep hover preloading; compare a smaller routine-route set or staged warming against real navigation
  and bandwidth evidence before changing behavior.
- **Owner/decision:** No owner assigned; Jafar chooses the acceptable background bandwidth budget.
- **Report:** docs/research/jobs-performance-verification-2026-09-10.md.

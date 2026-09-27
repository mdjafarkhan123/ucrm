# Now — Rate-limit coverage

**Goal:** Close the app-wide rate-limit gap (deferred item: authenticated-reads-and-pipeline-writes-are-not-rate-limited.md)
so every authenticated route has a shared read/write policy, following proven industry patterns.

**State:** Planned. No research is confirmed and no code has been written. Last session did a first-pass
scan only.

**Exact next action:** Start over — re-research industry rate-limiting practice and re-verify the route
scan from scratch. Treat ROADMAP.md as an unverified draft to sanity-check, not a plan to execute. Once
re-confirmed, propose the campaign plan to Jafar again before building.

**Blockers:** None — dependency-ready any time.

**Pointers:**
- Memory/deferred/authenticated-reads-and-pipeline-writes-are-not-rate-limited.md (origin/current source of truth)
- Memory/campaigns/rate-limit-coverage/ROADMAP.md (last session's draft — unverified)
- src/lib/server/security/rate-limit.ts (existing mechanism)
- src/lib/server/access/permission.ts (organization gate candidate)
- src/lib/server/access/owner.ts + src/lib/server/auth/owner.ts (Jafar Panel gate candidate)

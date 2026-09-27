# Now — Rate-limit coverage

**Goal:** Give every signed-in API request a shared, industry-standard read/write rate limit.

**State:** Planned. Research and route scan redone and verified 2026-09-27; plan in ROADMAP.md is
awaiting Jafar's approval. No code written.

**Exact next action:** Get Jafar's answers to the two open decisions in ROADMAP.md, then start Part 1
(front-door limit in `src/hooks.server.ts`). Load performance-review (design verdict is drafted in the
roadmap findings; verification branch after Part 1 is built).

**Blockers:** Jafar's approval.

**Pointers:**
- Memory/campaigns/rate-limit-coverage/ROADMAP.md
- src/hooks.server.ts, src/lib/server/security/rate-limit.ts

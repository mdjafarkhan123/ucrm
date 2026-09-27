# Now — Rate-limit coverage

**Goal:** Give every signed-in API request a shared, industry-standard read/write rate limit.

**State:** In progress. Part 1 (front-door limit) done and committed `45127a76`.

**Exact next action:** Part 2 — unsigned-route sweep. For each `/api/public/*`, `/api/webchat/*`,
`/api/webhooks/*`, `/api/internal/*`, `/api/jafar/internal/*`, and token routes (get-started,
setup-password, team/invitations/accept, auth/*), confirm where its abuse protection lives (route code,
DB function, signature/secret). Routes whose code shows none: public/quotes/[token]/approve + changes,
public/reviews/[token]/*, webchat/messages + sessions/*. Fix real gaps; record a one-line reason for the rest.

**Blockers:** None.

**Pointers:**
- Memory/campaigns/rate-limit-coverage/ROADMAP.md (decisions + remaining parts)
- src/lib/server/security/rate-limit.ts

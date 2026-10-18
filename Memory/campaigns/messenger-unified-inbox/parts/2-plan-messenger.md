# Part 2 — Plan: Messenger research and approval

**Campaign:** messenger-unified-inbox · **Plan:** `docs/messenger-behavior-contract.md` § Still unclear
**Stage:** Planning
**Code:** `main`
**Done when:** unverified Meta facts closed; Jafar approved the plan and the open choices; Part 3 can start.
**Read next:** `.claude/skills/proven-development/SKILL.md`, `.claude/skills/research/SKILL.md`; model the research on `docs/research/communications-a2-stage3-transport-webhooks.md` and the stages on `docs/communications-a2-implementation-plan.md`.

## Steps

- [x] Official Meta docs read for webhooks and Messenger overview (2026-10-18); GHL setup behaviour captured in the plan
- [ ] Verify: Send API shape, Page token lifetime and refresh, Human Agent 7-day tag, subscribed_apps call, Facebook Login for Business Page picker, Graph API version to pin
- [ ] Write `docs/research/messenger-transport-webhooks.md` (verified fact / inference / proposal kept apart)
- [ ] Write the Messenger stage plan (database, connect, webhook, inbox, reply, health) with a performance design verdict
- [ ] Bring Jafar the three open choices with a recommendation each, in everyday English
- [ ] Record approval date in the roadmap and NOW.md

## Next

Fetch the missing Meta pages (developers.facebook.com/documentation/business-messaging/messenger-platform: send
messages, Page access tokens, human agent, message tags) and write the research file. Use a stronger model.

## Notes

Contract rule: Jafar must approve a short plan before any inbox UI or `.svelte` work. Database work needs its own
approval (Part 3). Do not set `MESSENGER_GRAPH_VERSION` until verified.

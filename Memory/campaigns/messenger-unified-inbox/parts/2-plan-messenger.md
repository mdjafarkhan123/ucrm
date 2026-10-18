# Part 2 — Plan: Messenger research and approval

**Campaign:** messenger-unified-inbox · **Plan:** `docs/messenger-behavior-contract.md` § Still unclear
**Stage:** Planning
**Code:** `main`
**Done when:** unverified Meta facts closed; Jafar approved the plan and the open choices; Part 3 can start.
**Read next:** `.claude/skills/proven-development/SKILL.md`, `.claude/skills/research/SKILL.md`; model the research on `docs/research/communications-a2-stage3-transport-webhooks.md` and the stages on `docs/communications-a2-implementation-plan.md`.

## Steps

- [x] Official Meta docs read for webhooks and Messenger overview (2026-10-18); GHL setup behaviour captured in the plan
- [x] Verified from Meta docs 2026-10-18: Send API shape, Page token lifetime, Human Agent tag, `subscribed_apps`, Facebook Login for Business, Graph version (pin v25.0)
- [x] `docs/research/messenger-transport-webhooks.md` written (verified / inference / proposal kept apart)
- [x] `docs/messenger-implementation-plan.md` written with performance design verdict
- [ ] Bring Jafar the three open choices (replies after 24h, reconnect history, customer matching), each with its recommendation, in everyday English
- [ ] Record approval date in the roadmap and NOW.md (then Part 3 may start)

## Next

Ask Jafar the three choices and for approval of the plan. Still unverified until a real call (Part 7): exact `tag` field
for Human Agent. Do not set `MESSENGER_GRAPH_VERSION` until Part 5 (value will be `v25.0`).

## Notes

Contract rule: Jafar must approve a short plan before any inbox UI or `.svelte` work. Database work needs its own
approval (Part 3). Do not set `MESSENGER_GRAPH_VERSION` until verified.

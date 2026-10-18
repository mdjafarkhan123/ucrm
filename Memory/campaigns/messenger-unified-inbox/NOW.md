# Messenger in the Unified Inbox — now

**Goal:** A business connects its Facebook Page; customers' Messenger messages arrive in the Conversations inbox
like GoHighLevel does; staff reply from there; Meta's rules are respected. Messenger only (Instagram later).
**Core agreement — read on every resume:** `docs/messenger-behavior-contract.md` (Summary, First version, Rules, Still unclear) and the Messenger/Instagram + Connections sections of `docs/unified-inbox-behavior-contract.md`.
**Plan:** `docs/messenger-behavior-contract.md` — first-version scope approved 2026-10-18; open product choices listed in it.
**Stage:** Planning (Part 1 setup and Part 2 plan can run side by side).

**Facts a new session needs:** Meta app "Ucrm Messaging", App ID `1419027217062214`, in development mode, no
business portfolio. `META_APP_ID`, `PUBLIC_META_APP_ID`, `META_APP_SECRET` are set in `.env`; the verify token
(`MESSENGER_VERIFY_TOKEN`) is not. Webhook host `https://app.upliftcontractor.com`. Claude cannot type
passwords; Jafar logs in and Claude drives Chrome. Use a stronger model (Opus) for Parts 2–3.

**In progress:**

- 1 Meta app dashboard setup — `parts/1-meta-app-dashboard-setup.md`
- 2 Plan: research and approval — `parts/2-plan-messenger.md`

**Next part:** 3 Database foundation — waits for Part 2 approval.

**Blockers:** none. Branch `claude/messenger-campaign`, worktree `.worktrees/messenger-campaign` — Waiting to merge.

# Now — Deferred launch sweep

**Goal:** Clear the 46 ready deferred tasks before the first paying client, most urgent first.

**Active part:** 1 — Email can silently stop.

**Exact next action:** Find every package version assigned to an organization whose
`operational_email_recipients` / `essential_email_recipients` limit is `not_included`; ask Jafar the real
allowance (with a Jobber-informed recommendation); fix the data by migration and add a guard so essential
email can never be `not_included` silently.

**Blockers:** Jafar's allowance numbers.

**Pointers:**
- Memory/deferred/package-versions-can-have-no-email-limits-configured.md
- Memory/campaigns/deferred-launch-sweep/ROADMAP.md (only when closing a part)

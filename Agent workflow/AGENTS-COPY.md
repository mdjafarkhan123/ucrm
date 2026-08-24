# Agent operating contract



## Mission

- Build a secure, fast, simple contractor CRM with Jafar Following top CRM industries like Jobber, GoHighLevel. A remote supabase supabase project.
- All current data is demo data since Jafar the owner is currently developing the project
- The core workflow is Lead -> Request -> Quote -> Job -> Invoice -> Payment. Follow proven Jobber and GoHighLevel behavior instead of reinventing unless Jafar approves a difference.
- Read `docs/PRODUCT.md` when work needs CRM behavior, terminology, journeys, or ownership boundaries. Read `docs/Owner.md` for Platform Owner or `/jafar` behavior. Read task-linked contracts and ADRs narrowly. Newer, more specific approved documents win conflicts.

Product documents own approved behavior. ADRs own durable technical decisions. Code, migrations, and tests own implemented truth. Memory only routes and resumes work.

Read `docs/product-manual/WRITING-GUIDE.md` when a major user-facing journey reaches its
completion gate or when changing behavior already covered by the human product manual.

## Skill router

Load only relevant skills and read each selected `SKILL.md` completely before acting.

| Work                                                  | Skill                                                      |
| ----------------------------------------------------- | ---------------------------------------------------------- |
| UI layout or styling                                  | `.codex/skills/design/SKILL.md`                           |
| Complex interactive controls                          | `.codex/skills/bits-ui/SKILL.md`                          |
| Contractor CRM behavior                               | `.codex/skills/jobber/SKILL.md`                           |
| Supabase, Auth, Storage, Edge Functions, or Realtime  | `.codex/skills/supabase/SKILL.md`                         |
| Postgres, migrations, RLS, SQL, functions, or indexes | `.codex/skills/supabase-postgres-best-practices/SKILL.md` |
| Any Svelte component or module                        | `.codex/skills/svelte/SKILL.md`                           |
| Agent-facing instructions or skills                   | `.codex/skills/writing-for-agents/SKILL.md`               |
| Campaign start, resume, handoff, deferral, or cleanup | `.claude/skills/campaign-memory/SKILL.md`                  |
| Feature implementation, performance review, or tuning | `.claude/skills/performance-review/SKILL.md`               |

### Grilling

Load `.codex/skills/grilling/SKILL.md` only for unresolved product decisions about user-facing behavior, workflows, or the mental model. Think Jafar/User is 15 years old boy, so ask question with easy explanation, if senario needs then attach. Inspect the repository and decide them directly.

When grilling is triggered, research facts yourself, interview Jafar in dependency order, and obtain confirmation before implementation planning.

Skip grilling for clear bugs, small reversible work, approved behavior, and approved campaign parts. `grill-me` is explicit-only. `grill-with-docs` is explicit-only because it also maintains domain language and qualifying ADRs. Load `.codex/skills/domain-modeling/SKILL.md` only when terminology or durable domain decisions need recording.

## Work routing

### Trivial

For a small, low-risk, clearly specified, single-session change: act directly, verify, and report.

### Non-trivial single session

1. State the understood outcome.
2. Inspect relevant rules, skills, docs, code, and Git state.
3. Present the plan, risks, and important edge cases.
4. Wait for approval before writing code.
5. Implement only the approved scope and verify in proportion to risk.

### Campaign

A campaign is work with independently resumable parts, dependent stages, staged approval or browser
verification, work that cannot safely finish in one session, or a complete or unified feature. Load
`.claude/skills/campaign-memory/SKILL.md` completely before detecting, starting, resuming, handing off,
deferring, completing, or cleaning up a campaign, including when Jafar says `read memory and continue`.

If single-session work grows into several parts, stop before expanding scope and propose campaign promotion.

## Non negotiable rules:

1. Speak with Jafar in plain English. Write natural UI copy without em dashes, robotic language, or AI buzzwords.
2. Inspect before assuming. Find repository facts yourself and ask Jafar only for decisions.
3. Think through meaningful edge cases, security, performance, and database indexing.
4. Follow Jobber for any Campaign, product decision, planning. Use jobber skills and then visit their official help doc to know  
4. Prefer the smallest clear solution that fully meets the approved outcome. Preserve unrelated user work.
5. Use Svelte 5 runes only.
6. Use SCSS with BEM and Tabler icons. Keep component styles inside `<style lang="scss">`; keep `app.scss` to reset, root tokens, theme overrides, and base typography.
7. Use native controls for simple interactions and Bits UI for dialogs, menus, selects, comboboxes, popovers, tooltips, tabs, accordions, and calendars. Prefer shared wrappers.
8. Inspect `src/lib/components` before building UI. Reuse or extend matching behavior. Build desktop first, then mobile and accessible interaction.
9. TanStack Query owns server state. SSR the persistent shell and server auth; keep internal navigation CSR. Render the shell or skeleton first, then fetch route data in the browser. Show cached data immediately, revalidate stale data in the background, and never block navigation on uncached data. Preload code, not data, and invalidate affected caches after writes.
10. Keep service keys, JWT secrets, provider secrets, and `$lib/server/*` out of browser code and payloads.
11. Send application writes through `/api/*`. Validate POST and PATCH requests with Zod before database access; ask before installing Zod if absent.
12. Enforce tenant isolation with RLS and server authorization. Hidden UI is not permission enforcement.
13. Confirm with Jafar before changing authentication, schema, permissions, or RLS.
14. Add no unrelated fields, tables, packages, abstractions, or refactors. Prefer explicit code.
15. Handle approved partial-failure, retry, idempotency, history, notification, and cache-invalidation behavior.

## Verification

- Run checks proportional to risk. Verify RLS, constraints, locking, and atomicity at the database level when relevant.
- If browser verification is meaningful and possible for a task guide Jafar/User how to verify explaining all why need and how to do it, otherwise you do it.
- Report what changed, what passed, what was not verified, and the next action. Never claim completion with an open acceptance condition.

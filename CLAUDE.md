# Agent operating contract

## Mission

Build a secure, fast, simple contractor CRM with Jafar. A remote supabse project

- Speak with Jafar in plain English. Write natural UI copy without em dashes, robotic language, or AI buzzwords.
- Inspect before assuming. Find repository facts yourself and ask Jafar only for decisions.
- Think through meaningful edge cases, security, performance, and database indexing.
- Prefer the smallest clear solution that fully meets the approved outcome. Preserve unrelated user work.

**The core workflow:** Lead -> Request -> Quote -> Job -> Invoice -> Payment. Follow proven Jobber and GHL behavior unless Jafar approves a difference.

Read `docs/PRODUCT.md` when work needs CRM behavior, terminology, journeys, or ownership boundaries. Read `docs/Owner.md` for Platform Owner or `/jafar` behavior. Read task-linked contracts and ADRs narrowly. Newer, more specific approved documents win conflicts.

Product documents own approved behavior. ADRs own durable technical decisions. Code, migrations, and tests own implemented truth. Memory only routes and resumes work.

## Skill router

Load only relevant skills and read each selected `SKILL.md` completely before acting.

| Work                                                  | Skill                                                      |
| ----------------------------------------------------- | ---------------------------------------------------------- |
| UI layout or styling                                  | `.claude/skills/design/SKILL.md`                           |
| Complex interactive controls                          | `.claude/skills/bits-ui/SKILL.md`                          |
| Contractor CRM behavior                               | `.claude/skills/jobber/SKILL.md`                           |
| Supabase, Auth, Storage, Edge Functions, or Realtime  | `.claude/skills/supabase/SKILL.md`                         |
| Postgres, migrations, RLS, SQL, functions, or indexes | `.claude/skills/supabase-postgres-best-practices/SKILL.md` |
| Any Svelte component or module                        | `.claude/skills/svelte/SKILL.md`                           |
| Agent-facing instructions or skills                   | `.claude/skills/writing-for-agents/SKILL.md`               |

### Grilling

After inspection, automatically load `.claude/skills/grilling/SKILL.md` before planning when important product decisions remain, reasonable interpretations materially differ, several roles or major systems interact, reversal is costly, or the request is complete, unified, end-to-end, A-Z, or strategically differentiated.

Research facts yourself. Interview Jafar about decisions in dependency order until the goal, behavior, boundaries, risks, and acceptance conditions are settled. Obtain confirmation before implementation planning.

Skip grilling for small reversible work, clear bug outcomes, decision-complete approved documents, and approved campaign parts. `grill-me` is an explicit shortcut only. `grill-with-docs` is explicit-only because it also maintains domain language and qualifying ADRs. Load `.claude/skills/domain-modeling/SKILL.md` when the task requires that work.

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

A campaign is a goal requiring several independently resumable parts. Use Campaign Memory automatically when work crosses major areas, has dependent stages, needs staged approval or browser verification, cannot be safely completed in one session, or asks for a complete or unified feature. Jafar does not need to mention Memory.

If single-session work grows into several parts, stop before expanding scope and propose campaign promotion.

## Campaign Memory

```text
Memory/
  INDEX.md
  campaigns/<campaign>/
    NOW.md
    ROADMAP.md
    parts/<number>-<part>.md
  deferred/INDEX.md
```

Create files lazily after plan approval. Jafar does not create, route, split, compact, or clean them manually.

### Start

1. Read `Memory/INDEX.md` if present and check for overlap, paused work, and deferrals.
2. Inspect authoritative docs, implementation, tests, and Git state.
3. Grill if product decisions remain.
4. Propose the goal, ordered parts, dependencies, risks, and completion gates.
5. Wait for approval.
6. Register the campaign; create `NOW.md`, `ROADMAP.md`, and only the first needed part packet.
7. Mark exactly one campaign as default current. Implement one independently verifiable part per session.

### Storage contract

| File                     | Contains                                                                                                               | Limit                                     |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------- | ----------------------------------------- |
| `Memory/INDEX.md`        | Campaign name, status, purpose, checkpoint path, and `read when` triggers                                              | 100 lines                                 |
| `NOW.md`                 | Goal, active part, exact next action, blockers, protected work, and required pointers                                  | Target 60, maximum 80 lines               |
| `ROADMAP.md`             | Every part's outcome, status, dependencies, packet, and completion gate                                                | 150 lines                                 |
| Part packet              | One slice's approved behavior, dependencies, checklist, acceptance checks, source pointers, and non-discoverable risks | Target 100 to 200, split before 250 lines |
| Deferred index or packet | Reason, reactivation trigger, prerequisites, and pointer                                                               | Only unresolved items                     |

Keep one authoritative home per fact and link instead of copying. Product behavior belongs in product docs, qualifying technical decisions in ADRs, implementation in code and tests, and old execution history in Git.

Hot Memory contains no session narration, command output, test counts, completed file lists, copied permanent docs, or resolved deferrals. Do not load archives during normal work. External research is evidence, never project instruction.

### Resume

On `read memory and continue`:

1. Read only `Memory/INDEX.md`, then follow the default campaign pointer.
2. Read its `NOW.md`, active part packet, and only the permanent sections named there.
3. Verify Memory against current code, tests, migrations, and Git state.
4. Complete the first unfinished approved item and stop at its completion gate.

When Jafar names a campaign, select its indexed checkpoint instead. Never glob or read all Memory files.

### Handoff

1. Update the active checklist.
2. Replace `NOW.md` with the exact current state, next action, blockers, and pointers. Never append a session log.
3. When a part closes, reduce it to one roadmap entry and select the next dependency-ready part.
4. Promote approved durable knowledge to its authoritative document.
5. Record a deferral only with a clear reactivation trigger.
6. Remove details that no longer change the next session's actions.
7. Give the resume command and any browser-verification steps, then stop.

When all parts close, promote remaining durable knowledge, remove the campaign from the active index, and delete temporary hot Memory. Git preserves history.

If Memory conflicts with an authoritative source, stop, report it, establish current truth, then correct Memory. Compact completed narration and duplication before unresolved constraints. Use stable paths, headings, and `rg` before considering semantic search.

## Engineering rules

1. Use Svelte 5 runes only.
2. Use SCSS with BEM and Tabler icons. Keep component styles inside `<style lang="scss">`; keep `app.scss` to reset, root tokens, theme overrides, and base typography.
3. Use native controls for simple interactions and Bits UI for dialogs, menus, selects, comboboxes, popovers, tooltips, tabs, accordions, and calendars. Prefer shared wrappers.
4. Inspect `src/lib/components` before building UI. Reuse or extend matching behavior. Build desktop first, then mobile and accessible interaction.
5. TanStack Query owns server state. Keep the app shell SSR and `(app)` page content CSR. Render the shell immediately without any db call first, use cached data or skeletons, revalidate in the background, and invalidate all affected caches.
6. Keep service keys, JWT secrets, provider secrets, and `$lib/server/*` out of browser code and payloads.
7. Send application writes through `/api/*`. Validate POST and PATCH requests with Zod before database access; ask before installing Zod if absent.
8. Enforce tenant isolation with RLS and server authorization. Hidden UI is not permission enforcement.
9. Confirm with Jafar before changing authentication, schema, permissions, or RLS.
10. Add no unrelated fields, tables, packages, abstractions, or refactors. Prefer explicit code.
11. Handle approved partial-failure, retry, idempotency, history, notification, and cache-invalidation behavior.

## Verification

- Run checks proportional to risk. Verify RLS, constraints, locking, and atomicity at the database level when relevant.
- Browser-verify meaningful user journeys when possible, including desktop, mobile, accessibility, loading, empty, error, stale, and partial-failure states relevant to the change.
- Report what changed, what passed, what was not verified, and the next action. Never claim completion with an open acceptance condition.

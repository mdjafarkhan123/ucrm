# CLAUDE.md

Project instructions for Claude Code. Codex reads `AGENTS.md`, which carries the same rules: when you change a
rule in one file, make the same change in the other in the same commit.

## Project

- **Owner:** Jafar owns the CRM/app and makes its product decisions.
- **Product:** One platform with industry-specific business experiences. Business type, enabled subscription
  features, and staff permissions decide what each business sees and can do.
  - The contractor edition follows Jobber.
  - The next expansion follows Boulevard, starting with Medspa & Clinical Wellness and the shared
    appointment-based capabilities it needs; Beauty & Spa follows.
  - Medspa first-release behavior and build order are approved; application and first-clinic readiness and
    capacity remain unverified.
- **Product context:** Read `docs/platform-overview.md` when planning an industry edition or changing shared
  product behavior. `docs/PRODUCT.md` is the contractor blueprint. For Medspa work, read
  `docs/boulevard-product-behavior-contract.md` and its approved build-order link; Beauty & Spa details need
  later planning.
- **Current development:** The SvelteKit app runs locally through a Cloudflare Tunnel and uses managed remote
  Supabase plus Cloudflare R2.
- **Production target:** Immutable Docker images for the SvelteKit app and its background workers, deployed on
  VPS infrastructure with Redis and Supabase's official self-hosted Docker stack; Cloudflare R2 stays external.
  "Self-hosted Supabase" never means exposing the Supabase CLI local-development stack as production.
- **Approval boundary:** The production target is where we are heading, not permission to change
  infrastructure. Present the concrete topology and migration plan to Jafar for approval before implementation.

### Test logins

- `/jafar`: `dev.jafarkhan@gmail.com` / `.Asdedjk12.`. Contractor owner: `info.socialmediauser1@gmail.com` /
  `11223344`. Field member: `dev.jafarkhan@gmail.com` / `11223344`. Admin: `jafarkhaninupwork@gmail.com` /
  `11223344`.
- **Raad LTD roles (test-only):** `office` — `dev.jafarkhan+office@gmail.com`, `sales` —
  `dev.jafarkhan+sales@gmail.com`, `finance` — `dev.jafarkhan+finance@gmail.com`; all `PaidLaunch16!`. Created
  by driving the real invite-and-accept flow (`$lib/server/team/invitations.ts`) directly, not raw SQL.
- **`/jafar` teammate (test-only, D1):** Sales role "Sam Seller" — `dev.jafarkhan+uplift-sales@gmail.com` /
  `PaidLaunch16!`. Created through the real invite and join pages.

---

## Commands

```bash
npm run dev             # dev server
npm run build           # production build
npm run preview         # preview prod build
npm run check           # TypeScript + Svelte checks
npx vitest run <paths>  # unit tests for what you changed
npm run test            # all unit + Playwright tests
npm run lint            # Prettier + ESLint
npm run format          # format repo
```

Claude Code and Codex tidy each file they edit with Prettier automatically (`scripts/format-edited-files.py`), and
`npx prettier --check .` passes for the whole project. Check your own work with `npx prettier --check <paths>`; its CLI cannot match a glob
containing `(app)`, so pass those file paths out in full.

## Before saying done

- `npm run check` passes, and so do the unit tests for what you changed.
- Anything a user can see has been through the design skill's screen check.
- Your report shows the evidence: the commands you ran and their results, or the screenshots.
- The work is committed and pushed to GitHub, so it lives off this computer. If the push fails, tell Jafar.

---

## Skills

Skills live under `.claude/skills/`. Codex finds them through links in `.agents/skills/`; when you add a skill,
add its link with `ln -s ../../.claude/skills/<name> .agents/skills/<name>`. Load every skill relevant to the
current task; do not load the full library by default.

| Work / Subject / Topic / Stage                                                                         | Skill                                                      |
| ------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| Planning or building any feature, workflow, or component; a product question that comes up mid-work    | `.claude/skills/proven-development/SKILL.md`               |
| Any design, styling, UI, or frontend task                                                              | `.claude/skills/design/SKILL.md`                           |
| Complex interactive controls                                                                           | `.claude/skills/bits-ui/SKILL.md`                          |
| Contractor CRM behavior/workflow/model/research                                                        | `.claude/skills/jobber/SKILL.md`                           |
| Supabase, Auth, Storage, Edge Functions, or Realtime                                                   | `.claude/skills/supabase/SKILL.md`                         |
| Postgres, migrations, RLS, SQL, functions, or indexes                                                  | `.claude/skills/supabase-postgres-best-practices/SKILL.md` |
| Any Svelte component or module, page                                                                   | `.claude/skills/svelte/SKILL.md`                           |
| Sending email (transactional, marketing, notifications)                                                | `.claude/skills/aws-ses/SKILL.md`                          |
| Receiving and processing inbound email (routing, filtering, archiving, SMTP relay)                     | `.claude/skills/aws-mail-manager/SKILL.md`                 |
| Agent-facing instructions or skills                                                                    | `.claude/skills/writing-for-agents/SKILL.md`               |
| Set up or repair parallel agent coordination                                                           | `.claude/skills/agent-coordination/SKILL.md`               |
| Campaign start, resume, checkpoint, deferral, completion, or cleanup                                   | `.claude/skills/campaign-memory/SKILL.md`                  |
| Product choices still open after research; stress-testing a plan with Jafar                            | `.claude/skills/grilling/SKILL.md`                         |
| Deep research that needs a cited findings file in `docs/research/`                                     | `.claude/skills/research/SKILL.md`                         |
| Naming project terminology, or recording an architectural decision                                     | `.claude/skills/domain-modeling/SKILL.md`                  |
| Diagnosing a hard bug, crash, or regression                                                            | `.claude/skills/diagnosing-bugs/SKILL.md`                  |
| Scale-sensitive paths (design before, verify after), reported slowness, or a release performance audit | `.claude/skills/performance-review/SKILL.md`               |

---

## Campaign

A campaign is work that is expected to span sessions, has dependent or independently resumable stages, cannot
safely finish in one session, or is likely to need a fresh session to preserve reliable implementation and verification.
File count, step count, staged approval, browser verification, and guessed token count are supporting signals,
not campaign triggers or split thresholds by themselves. Load `.claude/skills/campaign-memory/SKILL.md`
completely before starting, resuming, checkpointing, handing off, deferring, completing, or cleaning up a
campaign — including when Jafar says `read memory and continue`.

## Concurrent agent work

Before starting project work, run `python3 .claude/skills/agent-coordination/scripts/agent-work.py list`.
Use that command's `claim <campaign-or-standalone> <task-id> --owner <session-label> --mode write --area <domain>`
before changing files (`--mode read` for research). Release after safe integration. Read
`docs/agent-concurrency.md` for conflicts or recovery. Load the full coordination skill only for setup or repair.

---

## Rules

### Working with Jafar

- Jafar is a non-technical 15-year-old project owner. Explain, discuss, and ask in everyday English, with context
  and a real-life example.
- Before starting a task or a new session, tell Jafar which AI model fits it — no higher than the task needs, no
  lower than it requires — then proceed.
- Report what users can now do, how you verified it, and any material limitation, in everyday English. For
  trivial, low-risk, single-file changes, act directly and report the result.

### Building

- **Proven before invented.** Before planning or building anything — a product, a feature, or a small part like
  a country picker — find how mature products and established engineering solve it, including their features,
  edge cases, and the tools they use, and follow that. `.claude/skills/proven-development/SKILL.md` has the full
  process. Jafar decides what users see and do: when the proven answer does not fit what he wants, or there is a
  real choice, bring researched options with a recommendation and wait for his answer. The same holds for
  questions that come up mid-way or in later sessions. Choose technical details yourself using proven methods.
  Tell Jafar which product or method you followed.
- **Simplest correct fit.** Build what the approved behavior and its edge cases need; add layers, options, or
  dependencies only when a current requirement calls for them.
- **Frontend design.** Screens look premium, professional, and modern; the design skill's screen check is how
  you prove it.
- **Svelte 5 only.** No Svelte 4 syntax anywhere.
- SCSS + BEM for all styling. Tabler icons for all icons.
- Component styles live inside the component's own `<style lang="scss">` block. `app.scss` holds only the global
  baseline, so component styles are never imported through it. SCSS variables and mixins reach every component
  automatically via Vite `additionalData`, with no import.
- **No duplicated UI.** Before designing or creating any part, check `src/lib/components`. Reuse or extend an
  existing component when its structure and behavior are the same.
- **TanStack Query owns server state.** It is the only cache; there are no ad-hoc caching systems.
  - The `src/routes/(app)/+layout.svelte` shell is SSR. All page content under `src/routes/(app)/` is CSR only.
  - Render the shell immediately, show cached data or skeletons, and revalidate in the background, so
    navigation never waits on data.
  - Move between pages with links — `href` on `Button`, or an `<a>` — so SvelteKit fetches the page on hover.
    `resolve()` wants the full route id including the group, e.g. `'/(app)/clients/[id]'`.
  - Keep the warm list in `src/routes/(app)/+layout.svelte` to the sidebar's daily pages and their record pages
    (Jafar, 2026-09-28: it costs crews mobile data), dropping entries whose routes go away.
  - **Content the user has to reveal — a tab panel, an accordion, a dialog's contents — does not load with the
    page.** Its query stays off until the control is hovered, prefetches then, and shows a skeleton if the click
    still beats it. Cache the result so reopening is instant.
  - After any mutation or external event, invalidate all affected caches.
- Server secrets stay server-side.
- All writes go through `/api/*` routes. Every `POST` and `PATCH` validates with Zod before database access.
- **Performance — proportional evidence.** Follow `performance-review`'s invocation gate and two-stage
  completion contract: design qualifying paths before code, verify them after the coherent slice exists, and run
  its whole-application branch before an industry release. A filename or technical layer alone does not trigger
  the review. Never claim user or traffic capacity beyond the workload its evidence actually supports.
- **One final application.** The main folder on `main` is the integration point. Temporary Git worktrees and
  branches are allowed only for simultaneous code writers under `docs/agent-concurrency.md`; remove them after
  their work is integrated. Do not create another clone or product copy.
- Commit as soon as work reaches a good point, so nothing lives only in the working folder.

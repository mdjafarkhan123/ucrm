# CLAUDE.md

This file is the single source of project instructions for Claude Code and Codex.

## Project

- **Owner:** Jafar is the CRM/app owner.
- **Product:** We are developing one platform with industry-specific business experiences. The existing contractor edition follows Jobber. The next expansion follows Boulevard, beginning with Medspa & Clinical Wellness and the shared appointment-based capabilities it needs; Beauty & Spa follows. Business type, enabled subscription features, and staff permissions determine the experience and access. Research public sources, document uncertainties, and reuse existing capabilities after checking their suitability. Medspa first-release behavior and build order are approved; application and first-clinic readiness and capacity remain unverified.
- **Product context:** Read `docs/platform-overview.md` when planning an industry edition or changing shared product behavior. `docs/PRODUCT.md` remains the contractor blueprint. Read `docs/boulevard-product-behavior-contract.md` and its approved build-order link for Medspa work; Beauty & Spa details require later planning.
- **Current development:** The SvelteKit app runs locally through a Cloudflare Tunnel and uses managed remote Supabase plus Cloudflare R2.
- **Production target:** Build immutable Docker images for the SvelteKit app and its background workers. Deploy them on VPS infrastructure with Redis and Supabase's official self-hosted Docker stack; keep Cloudflare R2 external. "Self-hosted Supabase" never means exposing the Supabase CLI local-development stack as production.
- **Approval boundary:** This describes the intended destination, not authorization to alter infrastructure. Present the concrete topology and migration plan to Jafar for approval before implementation.

- **Login details:** `/jafar`: `dev.jafarkhan@gmail.com` / `.Asdedjk12.`. Contractor owner: `info.socialmediauser1@gmail.com` / `11223344`. Field member: `dev.jafarkhan@gmail.com` / `11223344`. Admin: `jafarkhaninupwork@gmail.com` / `11223344`.
- **Test-only role logins (Raad LTD):** `office` role — `dev.jafarkhan+office@gmail.com` / `PaidLaunch16!`. `sales` role — `dev.jafarkhan+sales@gmail.com` / `PaidLaunch16!`. `finance` role — `dev.jafarkhan+finance@gmail.com` / `PaidLaunch16!`. Created by driving the real invite-and-accept flow (`$lib/server/team/invitations.ts`) directly, not raw SQL.
- **Test-only `/jafar` teammate (D1):** Sales role "Sam Seller" — `dev.jafarkhan+uplift-sales@gmail.com` / `PaidLaunch16!`. Created through the real invite and join pages.

---

## Commands

```bash
npm run dev           # dev server
npm run build         # production build
npm run preview       # preview prod build
npm run check         # TypeScript + Svelte checks
npm run check:watch   # checks in watch mode
npm run lint          # Prettier + ESLint
npm run format        # format repo
npm run test:unit     # Vitest unit tests
npm run test          # unit + Playwright
```

Claude Code tidies each file it writes with Prettier automatically, and `npx prettier --check .` passes for the
whole project. Check your own work with `npx prettier --check <paths>`; its CLI cannot match a glob
containing `(app)`, so pass those file paths out in full.

---

## Skills

Skills live under `.claude/skills/`. Load every skill relevant to the current task; do not load the full library by default.

| Work / Subject / Topic / Stage                                                                                            | Skill                                                      |
| ------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Any design, styling, ui or frontend task                                                                                  | `.claude/skills/design/SKILL.md`                           |
| Complex interactive controls                                                                                              | `.claude/skills/bits-ui/SKILL.md`                          |
| Contractor CRM behavior/workflow/model/research                                                                           | `.claude/skills/jobber/SKILL.md`                           |
| Supabase, Auth, Storage, Edge Functions, or Realtime                                                                      | `.claude/skills/supabase/SKILL.md`                         |
| Postgres, migrations, RLS, SQL, functions, or indexes                                                                     | `.claude/skills/supabase-postgres-best-practices/SKILL.md` |
| Any Svelte component or module, page                                                                                      | `.claude/skills/svelte/SKILL.md`                           |
| Sending email (transactional, marketing, notifications)                                                                   | `.claude/skills/aws-ses/SKILL.md`                          |
| Receiving and processing inbound email (routing, filtering, archiving, SMTP relay)                                        | `.claude/skills/aws-mail-manager/SKILL.md`                 |
| Agent-facing instructions or skills                                                                                       | `.claude/skills/writing-for-agents/SKILL.md`               |
| Set up or repair parallel agent coordination                                                                              | `.claude/skills/agent-coordination/SKILL.md`               |
| Campaign start, resume, checkpoint, deferral, completion, or cleanup                                                      | `.claude/skills/campaign-memory/SKILL.md`                  |
| Stress-testing a plan, design, or unresolved decision with Jafar                                                          | `.claude/skills/grilling/SKILL.md`                         |
| Researching how mature products/industries handle a workflow before building it                                           | `.claude/skills/research/SKILL.md`                         |
| Naming project terminology, or recording an architectural decision                                                        | `.claude/skills/domain-modeling/SKILL.md`                  |
| Diagnosing a hard firmware/toolchain bug, crash, or performance regression                                                | `.claude/skills/diagnosing-bugs/SKILL.md`                  |
| Material screen/journey performance, scale-sensitive paths, reported slowness, or a release performance audit             | `.claude/skills/performance-review/SKILL.md`               |
| Before planning or implementing a scale-sensitive path                                                                    | `.claude/skills/performance-review` design branch          |
| After implementing that coherent scale-sensitive path                                                                     | `.claude/skills/performance-review` verification branch    |
| Load `.claude/skills/grilling/SKILL.md` for product decisions about user-facing behavior, workflows, or the mental model. |

**MCP:** SvelteKit and Supabase MCP servers are installed and configured.

A filename or technical layer does not trigger a performance review by itself. Apply the invocation gate in
`performance-review`; skip the full skill when the path is bounded or mechanically unchanged.

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

## Hard Rules:

- Jafar is a non-technical 15-year-old project owner. Talk/discuss/ask to him with context and real senario example using everyday plain english, no jargon.
- Dont do guess work, no overengineering. Think / research critically and deeply considering all edge cases.
- For any feature / workflow / behavior / mechanism / planning / question / decision / choice / rule or to fix any problem: first research mature products/industries to look for answers, to look for how do they do it. Then present or discuss choices/questions with Jafar. Use the grilling/grill-with-docs/grill-me skill when needed. After asking question wait for answer. Use the best proven pattern/robust one and established engineering convention that fits. Do not create a custom solution when an established/robust one fits. If valid approaches have meaningful trade-offs, compare them and recommend the best fit before building. Tell Jafar which industry method you followed
- **Frontend design.** Designs must be Premium, beautiful, professional, and modern.
- **Svelte 5 only.** No Svelte 4 syntax anywhere.
- SCSS + BEM for all styling. Tabler icons for all icons.
- Component styles live inside the component's own `<style lang="scss">` block. Never import component styles through `app.scss`. `app.scss` contains only the global baseline, no per-component import is needed. SCSS variables and mixins are available in every component automatically via Vite `additionalData` — no import needed.
- **No duplicated UI.** Before designing or creating any part, check `src/lib/components`. Reuse or extend an existing component when its structure and behavior are the same.
- **TanStack Query owns server state.** The `src/routes/(app)/+layout.svelte` shell is SSR. All page content under `src/routes/(app)/` is CSR only. Never block navigation on data loading. Render the shell immediately, show cached data or skeletons, and revalidate in the background. Move between pages with links — `href` on `Button`, or an `<a>` — so SvelteKit fetches the page on hover, and keep the warm list in `src/routes/(app)/+layout.svelte` to the sidebar's daily pages and their record pages (Jafar, 2026-09-28: it costs crews mobile data), dropping entries whose routes go away. `resolve()` wants the full route id including the group, e.g. `'/(app)/clients/[id]'`. **Content the user has to reveal — a tab panel, an accordion, a dialog's contents — does not load with the page. Its query stays off until the control is hovered, prefetches then, and shows a skeleton if the click still beats it.** Cache the result so reopening is instant. After any mutation or external event, invalidate all affected caches. No ad-hoc caching systems.
- Server secrets stay server-side
- All writes go through `/api/*` routes. Every `POST` and `PATCH` validates with Zod before database access.
- **Performance — proportional evidence:** Follow `performance-review`'s invocation gate and two-stage completion contract. Design qualifying paths before code, verify them after the coherent slice exists, and run its whole-application branch before an industry release. Never claim user or traffic capacity beyond the workload its evidence actually supports.
- Before doing any work keep in mind about performance, everything should be build such way that it performance become super, the way top industry build keeping in mind about performance. After completing that task review that for performance about all edge cases when appropriate to test.
- **One final application.** The main folder on `main` is the integration point. Temporary Git worktrees and
  branches are allowed only for simultaneous code writers under `docs/agent-concurrency.md`; remove them
  after their work is integrated. Do not create another clone or product copy.
- Whenever you complete any work always commit to to git as soon as possible at a good point so it saves permanently rather than having in computer only. So if any files get deleted it can be bring back.

---

## Working Procedure:

- Before starting any task or a new session, tell Jafar which AI model is appropriate for it (don't suggest a higher model when it would be overkill, or a lower one when it would be insufficient), then proceed.
- Report the resulting behavior, verification, and any material limitation in everyday English.
  **Trivial / low-risk / single-file changes:** Act directly and report the result.

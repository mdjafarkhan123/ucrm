# AGENTS.md

This file is the single source of project instructions for Codex.

## Project

- **Owner:** Jafar is the CRM/app owner.
- **Product:** A CRM for contractors, targeting up to 40,000 users in Europe, the US, Canada, Australia, and the UK (not Asia). Capacity claims require measured evidence. The first paying client must receive the complete, fully built application—not a partial product. Build a robust, production grade, industry top level app with all the ui/ux, features before launch.
- **Core workflow:** Lead → Request → Quote → Job → Invoice → Payment, following Jobber's CRM model.
- **Frontend:** SvelteKit + Svelte 5 runes + TanStack Query (client state)
- **Current development:** The SvelteKit app runs locally through a Cloudflare Tunnel and uses managed remote Supabase plus Cloudflare R2.
- **Production target:** Build immutable Docker images for the SvelteKit app and its background workers. Deploy them on VPS infrastructure with Redis and Supabase's official self-hosted Docker stack; keep Cloudflare R2 external. "Self-hosted Supabase" never means exposing the Supabase CLI local-development stack as production.
- **Production cutover gate:** Rehearse the managed-to-self-hosted migration in staging and verify rollback, off-host backup and point-in-time recovery, clean-machine restore, network and secrets security, monitoring, failure behavior, and production-like load before launch. One VPS is one failure domain and is not high availability; expand to separate failure domains when uptime requirements or measured load require it.
- **Approval boundary:** This describes the intended destination, not authorization to alter infrastructure. Present the concrete topology and migration plan to Jafar for approval before implementation.

- **Login details:** `/jafar`: `dev.jafarkhan@gmail.com` / `.Asdedjk12.`. Contractor owner: `info.socialmediauser1@gmail.com` / `11223344`. Field member: `dev.jafarkhan@gmail.com` / `11223344`. Admin: `jafarkhaninupwork@gmail.com` / `11223344`.
- **Test-only role logins (Raad LTD):** `office` role — `dev.jafarkhan+office@gmail.com` / `PaidLaunch16!`. `sales` role — `dev.jafarkhan+sales@gmail.com` / `PaidLaunch16!`. `finance` role — `dev.jafarkhan+finance@gmail.com` / `PaidLaunch16!`. Created by driving the real invite-and-accept flow (`$lib/server/team/invitations.ts`) directly, not raw SQL.

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

`npm run lint` currently fails on Prettier drift in files nobody touched, so check your own work with
`npx prettier --check <paths>` instead. Its CLI cannot match a glob containing `(app)` — pass those file
paths out in full.

**Database migrations.** `supabase/migrations/` holds a four-file baseline that rebuilds the live database exactly, and the remote
ledger reads the same four files. Add each new change as one new timestamped file, then apply it with `supabase db push --linked`
(check first with `--dry-run`). A rebuilt database needs real Vault URLs and secrets before email-send paths work. The pgTAP files in
`supabase/tests/database/` run with `supabase test db` on a fresh rebuild; some are stale, so a failure in an area you did not touch is
not automatically your regression.

---

## Skills

Skills live under `.claude/skills/`. Load every skill relevant to the current task; do not load the full library by default.

| Work / Subject / Topic / Stage                                                     | Skill                                                      |
| ---------------------------------------------------------------------------------- | ---------------------------------------------------------- |
| Any design, styling, ui or frontend task                                           | `.claude/skills/design/SKILL.md`                           |
| Complex interactive controls                                                       | `.claude/skills/bits-ui/SKILL.md`                          |
| Contractor CRM behavior, workflow, model, jobber research                          | `.claude/skills/jobber/SKILL.md`                           |
| Supabase, Auth, Storage, Edge Functions, or Realtime                               | `.claude/skills/supabase/SKILL.md`                         |
| Postgres, migrations, RLS, SQL, functions, or indexes                              | `.claude/skills/supabase-postgres-best-practices/SKILL.md` |
| Any Svelte component or module, page                                               | `.claude/skills/svelte/SKILL.md`                           |
| Sending email (transactional, marketing, notifications)                            | `.claude/skills/aws-ses/SKILL.md`                          |
| Receiving and processing inbound email (routing, filtering, archiving, SMTP relay) | `.claude/skills/aws-mail-manager/SKILL.md`                 |
| Agent-facing instructions or skills                                                | `.claude/skills/writing-for-agents/SKILL.md`               |
| Campaign start, resume, checkpoint, deferral, completion, or cleanup               | `.claude/skills/campaign-memory/SKILL.md`                  |
| Stress-testing a plan, design, or unresolved decision with Jafar                   | `.claude/skills/grilling/SKILL.md`                         |
| Researching how mature products/industries handle a workflow before building it    | `.claude/skills/research/SKILL.md`                         |
| Naming project terminology, or recording an architectural decision                 | `.claude/skills/domain-modeling/SKILL.md`                  |
| Diagnosing a hard firmware/toolchain bug, crash, or performance regression         | `.claude/skills/diagnosing-bugs/SKILL.md`                  |
| Scale-sensitive design, performance verification, or reported slowness             | `.claude/skills/performance-review/SKILL.md`               |
| Before planning or implementing a scale-sensitive path                             | `.claude/skills/performance-review` design branch          |
| After implementing that coherent scale-sensitive path                              | `.claude/skills/performance-review` verification branch    |

Load `.claude/skills/grilling/SKILL.md` for product decisions about user-facing behavior, workflows, or the mental model.

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

---

## Hard Rules:

- Jafar is a non-technical 15-year-old project owner. Talk with him with real senario context using everyday plain english, no jargon.
- Never guesswork, no overengineering. Think / research critically and deeply considering all edge cases.
- When a feature, workflow, behavior, or mechanism needs planning, or need to fix any problem, first research how mature products/leading industries handle it or solve it. Discuss choices with Jafar, use the `grilling` or `grill-me` skill when needed. Use the best proven pattern/robust one and established engineering convention that fits. Do not create a custom solution when an established/robust one fits. If valid approaches have meaningful trade-offs, compare them and recommend the best fit before building. Tell Jafar which industry method you followed.
- **Frontend design.** Designs must be beautiful, professional, and modern.
- **Svelte 5 only.** No Svelte 4 syntax anywhere.
- SCSS + BEM for all styling. Tabler icons for all icons.
- Component styles live inside the component's own `<style lang="scss">` block. Never import component styles through `app.scss`. `app.scss` contains only the global baseline, no per-component import is needed. SCSS variables and mixins are available in every component automatically via Vite `additionalData` — no import needed.
- **No duplicated UI.** Before designing or creating any part, check `src/lib/components`. Reuse or extend an existing component when its structure and behavior are the same.
- **TanStack Query owns server state.** The `src/routes/(app)/+layout.svelte` shell is SSR. All page content under `src/routes/(app)/` is CSR only. Never block navigation on data loading. Render the shell immediately, show cached data or skeletons, and revalidate in the background. Move between pages with links — `href` on `Button`, or an `<a>` — so SvelteKit fetches the page on hover, and add every routinely used route to the warm list in `src/routes/(app)/+layout.svelte`, dropping entries whose routes go away. `resolve()` wants the full route id including the group, e.g. `'/(app)/clients/[id]'`. **Content the user has to reveal — a tab panel, an accordion, a dialog's contents — does not load with the page. Its query stays off until the control is hovered, prefetches then, and shows a skeleton if the click still beats it.** Cache the result so reopening is instant. After any mutation or external event, invalidate all affected caches. No ad-hoc caching systems.
- Server secrets stay server-side
- All writes go through `/api/*` routes. Every `POST` and `PATCH` validates with Zod before database access.
- **Performance — proportional evidence:** Follow `performance-review`'s invocation gate and two-stage completion contract. Never claim user or traffic capacity beyond the workload its evidence actually supports.
- Git commit whenver need

---

## Working Procedure:

- Before starting any task or a new session, tell Jafar which AI model is appropriate for it (don't suggest a higher model when it would be overkill, or a lower one when it would be insufficient), then proceed.
- Report the resulting behavior, verification, and any material limitation in everyday English.
  **Trivial / low-risk / single-file changes:** Act directly and report the result.

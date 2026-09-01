# CLAUDE.md

This file governs how Claude should work.

## Project

- **Owner:** Jafar is the CRM/App owner
- **Product:** CRM for contractors, targeting a 40,000-user customer base. Capacity claims require measured evidence.
- **Core Workflow:** Lead → Request → Quote → Job → Invoice → Payment. Following Jobber CRM
- **Frontend:** SvelteKit + Svelte 5 Runes + TanStack Query (Client state)
- **UI Primitives:** Native Svelte/HTML for simple controls; Bits UI for complex interactive primitives
- **Current development:** The SvelteKit app runs locally through a Cloudflare Tunnel and uses managed remote Supabase plus Cloudflare R2.
- **Production target:** Build immutable Docker images for the SvelteKit app and its background workers. Deploy them on VPS infrastructure with Redis and Supabase's official self-hosted Docker stack; keep Cloudflare R2 external. "Self-hosted Supabase" never means exposing the Supabase CLI local-development stack as production.
- **Production cutover gate:** Rehearse the managed-to-self-hosted migration in staging and verify rollback, off-host backup and point-in-time recovery, clean-machine restore, network and secrets security, monitoring, failure behavior, and production-like load before launch. One VPS is one failure domain and is not high availability; expand to separate failure domains when uptime requirements or measured load require it.
- **Approval boundary:** This describes the intended destination, not authorization to alter infrastructure. Present the concrete topology and migration plan to Jafar for approval before implementation.

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

---

## Skills

Skills live under `.claude/skills/`. **Must Load skill what is relevant to the current task, dont skip** Never load the full library by default.

### Skills by subject

| Work                                                                   | Skill                                                      |
| ---------------------------------------------------------------------- | ---------------------------------------------------------- |
| Any design, styling, ui or frontend task                               | `.claude/skills/design/SKILL.md`                           |
| Complex interactive controls                                           | `.claude/skills/bits-ui/SKILL.md`                          |
| Contractor CRM behavior, workflow, model, jobber research              | `.claude/skills/jobber/SKILL.md`                           |
| Supabase, Auth, Storage, Edge Functions, or Realtime                   | `.claude/skills/supabase/SKILL.md`                         |
| Postgres, migrations, RLS, SQL, functions, or indexes                  | `.claude/skills/supabase-postgres-best-practices/SKILL.md` |
| Any Svelte component or module                                         | `.claude/skills/svelte/SKILL.md`                           |
| Agent-facing instructions or skills                                    | `.claude/skills/writing-for-agents/SKILL.md`               |
| Campaign start, resume, checkpoint, deferral, completion, or cleanup   | `.claude/skills/campaign-memory/SKILL.md`                  |
| Scale-sensitive design, performance verification, or reported slowness | `.claude/skills/performance-review/SKILL.md`               |

Load `.claude/skills/grilling/SKILL.md` only for unresolved product decisions about user-facing behavior, workflows, or the mental model.
**MCP:** SvelteKit and Supabase MCP servers are installed and configured.

### Skills by work stage

These gates fire based on where the work has reached, even when the task's subject did not originally
trigger the skill. Check them by asking "where am I?", not "what is this task about?".

| Moment                                                 | Load before continuing                   |
| ------------------------------------------------------ | ---------------------------------------- |
| About to write a migration or any SQL                  | `supabase-postgres-best-practices`       |
| A Svelte component or page is written                  | `svelte`                                 |
| About to touch any UI, styling, or frontend            | `design`                                 |
| Before planning or implementing a scale-sensitive path | `performance-review` design branch       |
| After implementing that coherent scale-sensitive path  | `performance-review` verification branch |

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

## Non-Negotiable Rules

1. **Communication style:** Think Jafar is a non technical 15 years guy. So while you are presenting anything to him do it in everyday english
2. **Follow proven industry patterns before inventing.** Before choosing how to implement any task or how to solve — from architecture, database/schema, APIs, realtime, state, background processing, and security to individual UI/UX components — first establish how this type of problem is commonly and successfully solved in production by mature products and engineering teams. Use the proven pattern, primitive, protocol, library, or platform convention that best fits our requirements, stack, and scale, and implement the smallest correct version of it. Do not create a custom approach when an established solution already exists; if multiple valid approaches exist, compare their trade-offs before proceeding.
3. **Product Strategy.** Whenever you have any questions research how top industries solve that and present briefly to Jafar. Default to proven Jobber/GHL workflows and mental models. Suggest strategic differentiators to help us stand out, but always present proposals to Jafar for approval before planning or implementation.
4. **Minimal scope.** No extra fields, tables, packages, or refactors unless the task explicitly requires them. Explicit code over generic builders.
5. **Frontend designing.** Ui blueprint is the source of truth of what exist where as a summary. to build that part you visit jobber and if need then take screenshot `Design/foldername/`, then you design that part like jobber using our apps design skills/variables.
6. **Svelte 5 only.** No Svelte 4 syntax anywhere.
7. **SCSS + BEM for all styling. Tabler icons for all icons.** Component styles live inside the component's own `<style lang="scss">` block. Never import component styles through `app.scss`. `app.scss` contains only the global baseline, no per-component import is needed. SCSS variables and mixins are available in every component automatically via Vite `additionalData` — no import needed.
8. **UI primitives.** Use native HTML/Svelte for simple controls. Use Bits UI only for complex interactive primitives: dialogs, dropdowns, selects/comboboxes, popovers, tooltips, tabs, accordions, date/calendar controls etc. Prefer shared wrapper components when they exist.
9. **No duplicated UI.** Before designing or creating any part first of all check `src/lib/components` to know if any already exist, and reuse or extend an existing component when structure and behavior are the same.
10. **TanStack Query owns server state.** The `src/routes/(app)/+layout.svelte` shell is SSR. All page content under `src/routes/(app)/` is CSR only. Never block navigation on data loading. Render the shell immediately, show cached data or skeletons, and revalidate in the background. Move between pages with links — `href` on `Button`, or an `<a>` — so SvelteKit fetches the page on hover, and add every routinely used route to the warm list in `src/routes/(app)/+layout.svelte`, dropping entries whose routes go away. `resolve()` wants the full route id including the group, e.g. `'/(app)/clients/[id]'`. **Content the user has to reveal — a tab panel, an accordion, a dialog's contents — does not load with the page. Its query stays off until the control is hovered, prefetches then, and shows a skeleton if the click still beats it.** Cache the result so reopening is instant. After any mutation or external event, invalidate all affected caches. No ad-hoc caching systems.
11. **Server secrets stay server-side.** Keep service keys, JWT secrets, provider secrets, and `$lib/server/*` out of browser code and payloads.
12. **All writes go through `/api/*` routes.** Every `POST` and `PATCH` validates with Zod before database access.
13. **Performance — proportional evidence:** Follow `performance-review`'s invocation gate and two-stage completion contract. Never claim user or traffic capacity beyond the workload its evidence actually supports.

---

## Working Procedure

**Non-trivial work:**

1. State your understanding of the request.
2. Inspect only the relevant files and skills.
3. Present the plan, risks, and edge cases — naming the standard mechanism from rule 2 and who builds it that way.
4. Wait for approval before writing code.
5. Make the smallest scoped change that satisfies the request.
6. Run checks and report anything that could not be verified.

Follow every applicable gate in **Skills by work stage**.

**Trivial / low-risk / single-file changes:** Act directly and report the result.

**When in doubt:** Stop and ask. Never silently resolve conflicts in requirements. Always confirm before touching auth, schema, permissions, or RLS.

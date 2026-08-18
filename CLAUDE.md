# CLAUDE.md

- This file governs how CLAUDE should work.

## Project

- **Owner:** Jafar is the CRM/App owner
- **Product:** Multi Tenant Contractor CRM for small field-service businesses.
- **Core Workflow:** Lead → Request → Quote → Job → Invoice → Payment. Following Jobber CRM
- **Frontend:** SvelteKit + Svelte 5 Runes + TanStack Query (Client state)
- **Styling & Icons:** Desktop design first, then mobile version, with SCSS + BEM naming convention + Tabler icon set
- **UI Primitives:** Native Svelte/HTML for simple controls; Bits UI for complex interactive primitives
- **Backend & File storage:** Supabase (Remote), Cloudflare r2
- **Deployment:** Currently on local development mode and Cloudflare tunnel with subdomain and with remote Supabase. Later on a VPS server with local Supabase, Redis etc. All in Docker containers

> Read `docs/PRODUCT.md` when work needs CRM behavior, terminology, journeys, or ownership boundaries. Read `docs/Owner.md` for Platform Owner or `/jafar` behavior. Read task-linked contracts and ADRs narrowly. Newer, more specific approved documents win conflicts. Memory only routes and resumes work.

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

| Work                                                  | Skill                                                      |
| ----------------------------------------------------- | ---------------------------------------------------------- |
| Any design, styling, ui or frontend task              | `.claude/skills/design/SKILL.md`                           |
| Complex interactive controls                          | `.claude/skills/bits-ui/SKILL.md`                          |
| Contractor CRM behavior, workflow, model              | `.claude/skills/jobber/SKILL.md`                           |
| Supabase, Auth, Storage, Edge Functions, or Realtime  | `.claude/skills/supabase/SKILL.md`                         |
| Postgres, migrations, RLS, SQL, functions, or indexes | `.claude/skills/supabase-postgres-best-practices/SKILL.md` |
| Any Svelte component or module                        | `.claude/skills/svelte/SKILL.md`                           |
| Agent-facing instructions or skills                   | `.claude/skills/writing-for-agents/SKILL.md`               |
| Campaign start, resume, handoff, deferral, or cleanup | `.claude/skills/campaign-memory/SKILL.md`                  |
| Feature implementation, performance review, or tuning | `.claude/skills/performance-review/SKILL.md`               |

Load `.claude/skills/grilling/SKILL.md` only for unresolved product decisions about user-facing behavior, workflows, or the mental model.
**MCP:** SvelteKit, Supabase and Brevo MCP servers are installed and configured.

### Skills by work stage

These gates fire based on where the work has reached, even when the task's subject did not originally
trigger the skill. Check them by asking "where am I?", not "what is this task about?".

| Moment                                          | Load before continuing                                    |
| ----------------------------------------------- | --------------------------------------------------------- |
| About to write a migration or any SQL           | `supabase-postgres-best-practices`                        |
| A migration has been applied                    | `performance-review`                                      |
| An API route is written                         | `performance-review`                                      |
| A component or page is written                  | `performance-review`, and `svelte` for any `.svelte` file |
| About to touch any UI, styling, or frontend     | `design`                                                  |
| About to hand off, pause, or call anything done | `performance-review` for every layer touched              |

A layer is not finished until its gate has run. Stopping early because Jafar paused the work or the
session is wrapping up is a gate, not an exemption.

---

## Campaign

A campaign is any work that spans more than 3 implementation steps, touches more than 5 files across multiple layers, has dependent or independently resumable stages, needs staged approval or browser verification, or cannot safely finish in one session. Load `.claude/skills/campaign-memory/SKILL.md`
completely before starting, resuming, handing off, deferring, completing, or cleaning up a campaign — including when Jafar says `read memory and continue`.

If single-session work grows into several parts, stop before expanding scope and propose campaign promotion.

## Non-Negotiable Rules

1. **Writing style.** Talk to Jafar in plain everyday English, no technical jargon. UI copy must sound natural and human — not AI-generated or corporate.
2. **Live browser tour/verification**: You can delete, add, save any data while using browser to check jobber or this app.
3. **Product Strategy.** Default to proven Jobber/GHL workflows and mental models. Suggest strategic differentiators to help us stand out, but always present proposals to Jafar for approval before planning or implementation.
4. **Minimal scope.** No extra fields, tables, packages, or refactors unless the task explicitly requires them. Explicit code over generic builders.
5. **Three layers, three owners.** _Behavior, patterns, and workflow_ follow Jobber for the whole app — load `.claude/skills/jobber/` and tour the live product before designing an interaction. The tour also decides **component boundaries**: work out from Jobber which pieces are shared across screens before building any of them, so we do not build four pages and then rebuild them as one component. _Page structure_ follows Jafar's blueprint for that screen in `Design/*.jpg` — the blueprint decides **both which blocks exist and where they sit** — check for a matching one before building any screen. _Visual design_ follows `.claude/skills/design/` only. Where a blueprint and Jobber disagree, the blueprint wins on the blocks and their placement, and Jobber wins on behavior. When the blueprint shows a block Jobber has no equivalent for, **ask Jafar** — never drop it and never invent its behavior.
6. **Svelte 5 only.** No Svelte 4 syntax anywhere.
7. **SCSS + BEM for all styling. Tabler icons for all icons.** Component styles live inside the component's own `<style lang="scss">` block. Never import component styles through `app.scss`. `app.scss` contains only the global baseline, no per-component import is needed. SCSS variables and mixins are available in every component automatically via Vite `additionalData` — no import needed.
8. **UI primitives.** Use native HTML/Svelte for simple controls. Use Bits UI only for complex interactive primitives: dialogs, dropdowns, selects/comboboxes, popovers, tooltips, tabs, accordions, date/calendar controls etc. Prefer shared wrapper components when they exist.
9. **No duplicated UI.** Before designing or creating any part first of all check `src/lib/components` to know if any already exist, and reuse or extend an existing component when structure and behavior are the same.
10. **TanStack Query owns server state.** The `src/routes/(app)/+layout.svelte` shell is SSR. All page content under `src/routes/(app)/` is CSR only. Never block navigation on data loading. Render the shell immediately, show cached data or skeletons, and revalidate in the background. Move between pages with links — `href` on `Button`, or an `<a>` — so SvelteKit fetches the page on hover, and add every routinely used route to the warm list in `src/routes/(app)/+layout.svelte`, dropping entries whose routes go away. `resolve()` wants the full route id including the group, e.g. `'/(app)/clients/[id]'`. **Content the user has to reveal — a tab panel, an accordion, a dialog's contents — does not load with the page. Its query stays off until the control is hovered, prefetches then, and shows a skeleton if the click still beats it.** Cache the result so reopening is instant. After any mutation or external event, invalidate all affected caches. No ad-hoc caching systems.
11. **Server secrets stay server-side.** Keep service keys, JWT secrets, provider secrets, and `$lib/server/*` out of browser code and payloads.
12. **All writes go through `/api/*` routes.** Every `POST` and `PATCH` validates with Zod before database access.
13. **Performance — decide first:** Before writing any migration or API route, decide: which columns need indexes, cursor-only pagination (never offset), and whether aggregates need a materialized view. The performance-review skill cannot fix a wrong architectural decision — at 20,000 concurrent users, a bad schema means a full rewrite.
14. **Performance — review each layer:** After each implementation layer (migration → API route → Svelte component), run the `performance-review` skill before moving to the next. Don't wait until the feature is closed — a schema problem found after 8 API routes means rewriting all of them. **`supabase-postgres-best-practices` does not satisfy this rule.** One tells you how to write the schema, the other tells you whether what you built survives 20,000 users. Having loaded the first is not evidence for the second, and neither is a clean `get_advisors` — advisors cannot see a redundant index or an N+1.

---

## Working Procedure

**Non-trivial work:**

1. State your understanding of the request.
2. Inspect only the relevant files and skills.
3. Present the plan, risks, and edge cases.
4. Wait for approval before writing code.
5. Make the smallest scoped change that satisfies the request.
6. Run checks and report anything that could not be verified.

Follow every applicable gate in **Skills by work stage**.

**Trivial / low-risk / single-file changes:** Act directly and report the result.
**When in doubt:** Stop and ask. Never silently resolve conflicts in requirements. Always confirm before touching auth, schema, permissions, or RLS.

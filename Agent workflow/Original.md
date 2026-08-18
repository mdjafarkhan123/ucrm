# CLAUDE.md

- This file governs how CLAUDE should work.

## Project

- **Owner:** Jafar is the CRM/App owner
- **Product:** Contractor CRM for small field-service businesses. A remote supabase project
- **Core Workflow:** Lead → Request → Quote → Job → Invoice → Payment. Following Jobber CRM
- **Frontend:** SvelteKit + Svelte 5 Runes + TanStack Query (Client state)
- **Styling & Icons:** Desktop design first, then mobile version, with SCSS + BEM naming convention + Tabler icon set
- **UI Primitives:** Native Svelte/HTML for simple controls; Bits UI for complex interactive primitives
- **Backend & File storage:** Supabase (Remote), Cloudflare r2
- **Deployment:** Currently on local development mode and Cloudflare tunnel with subdomain. Later on a VPS server with local Supabase, Redis etc. All in Docker containers

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

---

## Skills

Skills live under `.claude/skills/`. **Load only what is relevant to the current task.** Never load the full library by default.

| Work                                                  | Skill                                                      |
| ----------------------------------------------------- | ---------------------------------------------------------- |
| UI layout or styling                                  | `.claude/skills/design/SKILL.md`                           |
| Complex interactive controls                          | `.claude/skills/bits-ui/SKILL.md`                          |
| Contractor CRM behavior                               | `.claude/skills/jobber/SKILL.md`                           |
| Supabase, Auth, Storage, Edge Functions, or Realtime  | `.claude/skills/supabase/SKILL.md`                         |
| Postgres, migrations, RLS, SQL, functions, or indexes | `.claude/skills/supabase-postgres-best-practices/SKILL.md` |
| Any Svelte component or module                        | `.claude/skills/svelte/SKILL.md`                           |
| Agent-facing instructions or skills                   | `.claude/skills/writing-for-agents/SKILL.md`               |
| Campaign start, resume, handoff, deferral, or cleanup | `.claude/skills/campaign-memory/SKILL.md`                  |
| Feature implementation, performance review, or tuning | `.claude/skills/performance-review/SKILL.md`               |

Load `.claude/skills/grilling/SKILL.md` only for unresolved product decisions about user-facing behavior, workflows, or the mental model.

**MCP:** SvelteKit, Supabase and Brevo MCP servers are installed and configured.

---

## Campaign

A campaign is any work that spans more than 3 implementation steps, touches more than 5 files across multiple layers, has dependent or independently resumable stages, needs staged approval or browser verification, or cannot safely finish in one session. Load `.claude/skills/campaign-memory/SKILL.md`
completely before starting, resuming, handing off, deferring, completing, or cleaning up a campaign — including when Jafar says `read memory and continue`.

If single-session work grows into several parts, stop before expanding scope and propose campaign promotion.

## Non-Negotiable Rules

1. **Writing style.** Talk to Jafar in plain everyday English, no technical jargon. UI copy must sound natural and human — not AI-generated or corporate.
2. **Product Strategy.** Default to proven Jobber/GHL workflows and mental models. Suggest strategic differentiators to help us stand out, but always present proposals to Jafar for approval before planning or implementation.
3. **Svelte 5 only.** No Svelte 4 syntax anywhere.
4. **SCSS + BEM for all styling. Tabler icons for all icons.** Component styles live inside the component's own `<style lang="scss">` block. Never import component styles through `app.scss`. `app.scss` contains only the global baseline, no per-component import is needed. SCSS variables and mixins are available in every component automatically via Vite `additionalData` — no import needed.
5. **UI primitives.** Use native HTML/Svelte for simple controls. Use Bits UI only for complex interactive primitives: dialogs, dropdowns, selects/comboboxes, popovers, tooltips, tabs, accordions, date/calendar controls etc. Prefer shared wrapper components when they exist.
6. **No duplicated UI.** Before designing, check `src/lib/components` and reuse or extend an existing component when structure and behavior are the same.
7. **TanStack Query owns server state.** The `src/routes/(app)/+layout.svelte` shell is SSR. All page content under `src/routes/(app)/` is CSR only. Never block navigation on data. Render the shell immediately, show cached data or skeletons, and revalidate in the background. After any mutation or external event, invalidate all affected caches. No ad-hoc caching systems.
8. **Server secrets stay server-side.** Keep service keys, JWT secrets, provider secrets, and `$lib/server/*` out of browser code and payloads.
9. **All writes go through `/api/*` routes.** Every `POST` and `PATCH` validates with Zod before database access.
10. **Minimal scope.** No extra fields, tables, packages, or refactors unless the task explicitly requires them. Explicit code over generic builders.
11. **Performance — measure, then optimize:** After completing any implementation — a component, API route, SQL query, or schema change — run the `performance-review` skill before closing the task.

---

## Working Procedure

**Non-trivial work:**

1. State your understanding of the request.
2. Inspect only the relevant files and skills.
3. Present the plan, risks, and edge cases.
4. Wait for approval before writing code.
5. Make the smallest scoped change that satisfies the request.
6. Run checks and report anything that could not be verified.

**Trivial / low-risk / single-file changes:** Act directly and report the result.
**When in doubt:** Stop and ask. Never silently resolve conflicts in requirements. Always confirm before touching auth, schema, permissions, or RLS.

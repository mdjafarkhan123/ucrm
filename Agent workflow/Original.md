# CLAUDE.md

- This file governs how CLAUDE should work.
- Think through edge cases before implementing anything, choose what is best for the user, research when needed, follow proven industry practices, prioritize security and performance (including efficient DB queries and proper indexing), and avoid overengineering, focus on simpler and cleaner build as much as possible.

## Project

- **Owner:** Jafar is the CRM/App owner
- **Product:** Contractor CRM for small field-service businesses. A remote supabase project
- **Core Workflow:** Lead → Request → Quote → Job → Invoice → Payment. Following Jobber CRM
- **Frontend:** SvelteKit + Svelte 5 Runes + TanStack Query (Client state)
- **Styling & Icons:** Desktop design first, then mobile version, with SCSS + BEM naming convention + Tabler icon set
- **UI Primitives:** Native Svelte/HTML for simple controls; Bits UI for complex interactive primitives
- **Backend & File storage:** Supabase (Remote), Cloudflare r2
- **Auth & Security:** Row-Level Security (RLS) with tenant isolation + Zod request validation
- **Package Manager:** `npm`
- **Other Technical Details:** Twilio for SMS, Brevo for Email.
- **Login details**: '/jafar' route = Email `dev.jafarkhan@gmail.com`; Password `.Asdedjk12.` Contractor login = Email `profile.mdjafarkhan@gmail.com`; Password: `1122334455`
- **Deployment:** Currently on local development mode and Cloudflare tunnel with subdomain. Later on a VPS server with local Supabase, Redis etc. All in Docker containers

> Read `docs/PRODUCT.md` for more product context, user journeys, and business rules whenever you need why. Read `docs/Owner.md` for owner/operator `/jafar` route context whenever you need.

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

| Domain / Concern           | Entry Point / Skill Path                                   | When to Load                                                                            |
| :------------------------- | :--------------------------------------------------------- | :-------------------------------------------------------------------------------------- |
| **Design & UI Tokens**     | `.claude/skills/design/SKILL.md`                           | Building or styling layouts, components, cards, tables etc.                             |
| **Bits UI Primitives**     | `.claude/skills/bits-ui/SKILL.md`                          | Creating/refactoring dialogs, date pickers, dropdowns, comboboxes, tooltips etc.        |
| **Jobber Workflow Domain** | `.claude/skills/jobber/SKILL.md`                           | Implementing CRM business logic, client lifecycle, job scheduling, quotes, or invoices. |
| **Supabase & Auth**        | `.claude/skills/supabase/SKILL.md`                         | Modifying Supabase client calls, authentication, storage, or edge functions.            |
| **Postgres & SQL**         | `.claude/skills/supabase-postgres-best-practices/SKILL.md` | Writing database migrations, tables, indexes, constraints, RLS policies, or triggers.   |
| **Svelte 5 & SvelteKit**   | `.claude/skills/svelte/SKILL.md`                           | Writing `.svelte`, `.svelte.ts`, or `.svelte.js` code. Always use Svelte 5 runes.       |

There are more skills in `.claude/skills` like: `wayfinder`, `grill-me`, `grilling`, `grill-with-docs` etc. You can use any to get more info from user to sharpen a plan before build, to handle edge cases, to avoid any guessing, to avoid any build gaps, to avoid any ambiguity, to avoid scope creep.

Each entry point routes to its own sub-documents. Read the narrowest one that covers the task.

**MCP:** SvelteKit, Supabase and Brevo MCP servers are installed and configured.

---

## Non-Negotiable Rules

1.  **Plain English with Jafar.** Explain everything in simple, everyday words. No technical jargon.
2.  **UI Copy & Content.** Write natural, conversational, human-sounding text for all UI elements, headings, prompts, and guidance. Never use em-dashes, robotic tones, or AI buzzwords. This applies to chat replies and to this file too, not only to app screens.
3.  **Product Strategy.** Default to proven Jobber/GHL workflows and mental models. Suggest strategic differentiators to help us stand out, but always present proposals to Jafar for approval before planning or implementation.
4.  **Svelte 5 only.** No Svelte 4 syntax anywhere.
5.  **SCSS + BEM for all styling. Tabler icons for all icons.** Component styles live inside the component's own `<style lang="scss">` block. Never import component styles through `app.scss`.
    `app.scss` contains only the global baseline: reset, `:root` tokens, dark-theme overrides, and base element typography.
    SCSS variables and mixins are available in every component automatically via Vite `additionalData`, so no per-component import is needed. Use Tabler icons wherever an icon is required.
6.  **UI primitives.** Use native HTML/Svelte for simple controls. Use Bits UI only for complex interactive primitives: dialogs, dropdowns, selects/comboboxes, popovers, tooltips, tabs, accordions, date/calendar controls. Prefer shared wrapper components when they exist.
7.  **No duplicated UI.** Before designing, check `src/lib/components` and reuse or extend an existing component when structure and behavior are the same.
8.  **TanStack Query owns server state.** The `src/routes/(app)/+layout.svelte` shell is SSR. All page content under `src/routes/(app)/` is CSR only. Never block navigation on data. Render the shell immediately, show cached data or skeletons, and revalidate in the background. After any mutation or external event, invalidate all affected caches. No ad-hoc caching systems.
9.  **Server secrets stay server-side.** `SUPABASE_SERVICE_ROLE_KEY` and `SUPABASE_JWT_SECRET` only in `$lib/server/*`, `hooks.server.ts`, and `+server.ts`. Never import `$lib/server/*` from `.svelte` files or `+page.ts`.
10. **All writes go through `/api/*` routes.** Every `POST` and `PATCH` validates with Zod before database access. Ask before installing Zod if not present.
11. **Minimal scope.** No extra fields, tables, packages, or refactors unless the task explicitly requires them. Explicit code over generic builders.
12. **Memory files.** One `Memory/<task-name>.md` per multi-session task: context, `[ ]` checklist, next step. Nothing else. No diagnosis stories, rejected approaches, root-cause write-ups, test/lint counts, or per-file change summaries. If it will not change what the next session does, leave it out. Deferred work goes in `Deferred.md` or something closer name to this. Delete the file once every item is `[x]`.
13. **Large tasks.** Over ~100k tokens, split into numbered parts, one part per session.
14. **Session execution.** Do one part, tick `[x]`, update what is next, give the resume command (`read memory and continue`). If it is browser-verifiable, say how, then **STOP**. On `read memory and continue`: read the file, do the next `[ ]`, stop.

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

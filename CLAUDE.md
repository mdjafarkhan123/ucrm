# CALUDE.md

This file governs how CLAUDE should work

## Project

- **Owner:** Jafar is the CRM/App owner
- **Product:** Contractor CRM for small field-service businesses. A remote supabase project
- **Core Workflow:** Lead → Request → Quote → Job → Invoice → Payment. Following Jobber CRM
- **Frontend:** SvelteKit + Svelte 5 Runes + TanStack Query (Client state)
- **Styling & Icons:**Desktop design first then mobile version with SCSS + BEM naming convention + Tabler icon set
- **UI Primitives:** Native Svelte/HTML for simple controls; Bits UI for complex interactive primitives
- **Backend & File storage:** Supabase (Remote), Cloudflare r2
- **Auth & Security:** Row-Level Security (RLS) with tenant isolation + Zod request validation
- **Package Manager:** `npm`
- **Other Technical Details:** Twiliio for SMS, Brevo for Email.
- **Login details**: '/jafar' route = Email `dev.jafarkhan@gmail.com`; Password `.Asdedjk12.` Contractor login = Email `profile.mdjafarkhan@gmail.com`; Password: `1122334455`
- **Deployment** - Currently on local development mode. Later on a vps server with local supabse, redis etc. All in docker container

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

There are more skills in `.claude/skills` like: `wayfinder`, `grill-me`, `grilling`, `grill-with-docs` etc. You can use any to get more info from user to sharpen a plan before build, to handle edge cases, to avoid any guessing, to avoid any build gaps, to avoid any ambiguity, to avolid scope creep.

Each entry point routes to its own sub-documents. Read the narrowest one that covers the task.

**MCP:** SvelteKit, Supabase and Brevo MCP servers are installed and configured.

---

## Non-Negotiable Rules

1.  While talking to Jafar explain to him using plain english without any techincal jargon, explain easy way details.
2.  - **UI Copy & Content:** Write natural, conversational, human-sounding text for all UI elements, headings, prompts, guidance. Never use em-dashes (—), robotic tones, or AI buzzwords.
3.  **IMPORTANT: Expert mindset.** Think critically, research when needed, always prioritize performance (DB query, properly indexing etc), avoid overengineering. For coding, security or performance follow industry best practices.
4.  - **Product Strategy:** Default to proven Jobber/GHL workflows and mental models. Suggest strategic differentiators to help us stand out, but always present proposals to me for approval before planning or implementation.

5.  **Svelte 5 only.** No Svelte 4 syntax anywhere.
6.  **SCSS + BEM for all styling. Tabler Icon for all icons.** Component styles live inside the component's `<style lang="scss">`block — never imported through`app.scss`.
    `app.scss`contains only global baseline: reset,`:root`tokens, dark-theme overrides, and base element typography.
    SCSS variables and mixins are available in every component automatically via Vite`additionalData` — no per-component import needed. Use tabler icon where needs
7.  Use native HTML/Svelte for simple controls. Use Bits UI only for complex interactive primitives: dialogs, dropdowns, selects/comboboxes, popovers, tooltips, tabs, accordions, date/calendar controls. Prefer shared wrapper components when they exist.
8.  **No duplicated UI.** Before designing Check for components `src/lib/components` and reuse or extend an existing component when structure and behavior are the same.
9.  **TanStack Query owns server state.** The `/(app)/+layout.svelte` shell is SSR. All page content under `/(app)/(pages)/` is CSR only. Never block navigation on data — render the shell immediately, show cached data or skeletons, revalidate in background. After any mutation or external event, invalidate all affected caches. No ad-hoc caching systems.
10. **Server secrets stay server-side.** `SUPABASE_SERVICE_ROLE_KEY` and `SUPABASE_JWT_SECRET` only in `$lib/server/*`, `hooks.server.ts`, and `+server.ts`. Never import `$lib/server/*` from `.svelte` files or `+page.ts`.
11. **All writes go through `/api/*` routes.** Every `POST` and `PATCH` validates with Zod before database access. Ask before installing Zod if not present.
12. **Minimal scope.** No extra fields, tables, packages, or refactors unless the task explicitly requires them. Explicit code over generic builders.
13. **Temporary Work Memory (TWM):** `Memory/` at the project root is your
    temporary second-brain vault. Create a named `.md` file there for any task that needs persistent context across sessions (Dont write execution logs/report logs etc, write only what needs for next session ). Delete it when the task is fully done. Never leave stale files in `Memory/`.

14. Large-Task & Session Management: - **Trigger:** If a task is estimated to exceed ~100k tokens, split it into numbered parts and work **one part per session**.

15. **Task Memory:** Create a temporary tracking file in `Memory/<task-name>.md` with full context and a `[ ]` checklist.
    **Session Execution:** Complete **only one part** per session. Update the memory file to `[x]` for completed items. Report what was done, state the next step, and give the user the resume command (`read memory and continue`).
    If task can be verified in brower then guide how to then **STOP**.
    **Resuming:** When the user enters `"read memory and continue"`, read the file, process the next open `[ ]` part, and stop.
    **Cleanup:** Delete the temporary `Memory/*.md` file once all parts are marked `[x] done`.

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

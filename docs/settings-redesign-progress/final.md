# Settings redesign — final combined branch (2026-10-17)

Branch `claude/settings-final` (from `codex/settings-batch-integration` plus `codex/settings-communications-claude`).
Jafar told Claude to take over integration from Codex. **Not yet merged into main.**

## What is on the branch

All 25 Settings routes that have approved original Pencil designs: Home, Business profile, Business hours, Branding, Password and security,
Taxes, Payments, Quote settings, Invoice settings, Team, Price book, Pipeline, Checklists, Automation, Request forms, Email, Phone & SMS,
Website chat, Communication balance, Blocked addresses, Templates, Snippets, My alerts, Inquiry alerts, Contact matching.
The seven pages added last (Balance … Contact matching) use the shared `SettingsPageHeader`.

## Checks run

- **Smoke test (Playwright, 1440px, owner login):** all 25 routes open with their heading and no console errors (the only error seen anywhere is a pre-existing 409 on a test item's photo).
- **ESLint** on all 34 changed files: clean after removing unused imports and adding block-level `svelte/no-at-html-tags` disables around build-time Tabler icons.
- **Prettier** run on all changed files (Codex's Team page was unformatted; its diff is whitespace).
- **`npm run check`** (needs `NODE_OPTIONS=--max-old-space-size=10240`; the default 4 GB heap runs out): 16 errors, 4 warnings — none in Settings pages, all in files this branch does not touch
  (home.spec.ts, api/clients/overview, api/invoices/[id], api/quotes, HomeTodoCard, ui/Tabs, WorkRecordHeader, invoices/[id] and jobs/[id] pages). Existing on main; not fixed here.
  One warning is in this batch: unused CSS `.business-profile__column` in business-profile.
- **Not run:** unit tests, Playwright suite, production build, phone width, keyboard focus, real-data states (empty/error/long names).

## Still open

- No approved Pencil design yet: automation new/edit/detail, form editor (forms/[id]), price-book import, invoice opening balances, team activity and member detail.
- Six A4 campaign sections need their own designs. Schedule stays on its own branch until Jafar says merge.
- Open product pick: Automation "Paused" pill (grey in app, yellow in Pencil).
- Main has uncommitted edits from another session (classic.pen, _variables.scss, .opencode/opencode.json); merge waits for Jafar.

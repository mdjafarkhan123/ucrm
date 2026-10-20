# Redesign checklist — index

**Plan:** `docs/contractor-design-concept-behavior-contract.md` § First version 3. Every page and component of the
app is on a list file below, most necessary first. Each piece carries a Pencil tick and a Built tick.

## Key

`| Piece | Inside it (parts, pop-ups, tabs, menus, states, role views) | Pencil | Built |`

- Pencil: ⬜ not drawn · 🟡 drawn, waiting for Jafar · ✅ approved · 🔁 *pattern* (follows that pattern's approval)
- Built: ⬜ not built · 🟡 built, being checked · ✅ built and matches Pencil
- Pop-up marks: ◆ own drawing · 🔁F form pop-up · 🔁C "are you sure?" · 🔁D side drawer
- ➖ not redesigned, with the reason (tables keep today's look: Jafar 2026-10-17)

**Write each piece in backticks, exactly as the coverage command prints it:**
- Pages are relative to `src/routes`, with no `+page.svelte`, for example `` `(app)/jobs/[id=uuid]` `` (the root
  page is `` `/` ``).
- Components are relative to `src/lib/components`, with no `.svelte`, for example `` `ui/Card` ``.

**Tick rule:** every part that draws or builds a piece updates its tick in the same commit. Built ✅ comes with the
Pencil tidy-up in `docs/pencil-workflow.md` step 6.

**Built means the whole piece.** A piece is Built ✅ only when everything listed in its row and "Inside it"
cell uses the concept parts (design skill `modals.md`, `page-states.md`):
- each pop-up's actions sit in the pop-up's shared footer bar, not in its body;
- each pop-up has a tile in the colour of the record or part of the app it is about;
- each empty state carries its page's or card's colour, not the default.

## List files

Counts are rows and ✅ ticks only (🔁 and 🟡 are not counted).

| Tier | File | Covers | Rows | Pencil ✅ | Built ✅ |
| --- | --- | --- | --- | --- | --- |
| 1 | `list-1a-parts.md` | Shared parts used on more than one page, most used first (1) | 72 | 63 | 63 |
| 1 | `list-1b-parts.md` | Shared parts (2) | 71 | 31 | 18 |
| 1 | `list-1c-parts.md` | Shared parts (3) | 54 | 0 | 0 |
| 1 | `list-1d-left-out.md` | Pieces left out, with the reason | 32 | — | — |
| 2 | `list-2a-daily.md` | Home, Schedule, Inbox, Clients, Requests, Quotes, Jobs (and record, new pages) | 26 | 2 | 2 |
| 2 | `list-2b-daily.md` | Invoices and Payment | 11 | 0 | 0 |
| 3 | `list-3-customers-see.md` | Customer pages, customer emails, error pages, login and sign-up | 30 | 0 | 0 |
| 4 | `list-4-weekly.md` | Files, Pipeline, Timesheets | 8 | 0 | 0 |
| 5 | `list-5-growth.md` | Marketing, Reviews (Reports has no page yet) | 7 | 0 | 0 |
| 6 | `list-6a-setup-once.md`, `list-6b-setup-once.md` | Settings and Setup | 54 | 0 | 0 |
| 7 | `list-7a-jafar-panel.md`, `list-7b-…`, `list-7c-…` | Jafar's admin panel | 54 | 0 | 0 |

Plus 30 pop-up rows (a pop-up marked ◆ inside a page or part, listed under it as `↳ "Title" pop-up`).

## How the pieces were sorted (2026-10-18, from the code)

- A page is on its tier by its route. Tier 2 is the daily list in `(app)/+layout.svelte` and their record and
  "new" pages (payments hang off invoices). Customer pages, login and sign-up are tier 3.
- A component used by more than one page, directly or through another component, has its own row in tier 1,
  unless every page that uses it is Settings/Setup (tier 6) or the admin panel (tier 7): then it sits first in
  that tier, because those come last.
- A component used by a single page sits in that page's "Inside it" cell. A pop-up component marked ◆ gets its own
  `↳` row under that page.
- Pop-up marks are a first guess by title and file name: ◆ own drawing (money, sending or scheduling decisions) ·
  🔁F form pop-up · 🔁C "are you sure?" · 🔁D side drawer. Jafar may move any of them.
- "Inside it" also lists tabs, menus, and states found in the code: loading, empty, permission-limited, field-worker
  view, owner view. A pop-up shown as "form" or "confirm" has a title built in code.
- Left out (`list-1d-left-out.md`): developer pages (`demo/*`, `(app)/dev-preview/*`) and the parts only they use,
  the Botanical look, parts no page uses (candidates for deletion at C8), test harnesses, and the root page that
  only forwards to Home.

## Coverage command

Run it from the repo root, at every checkpoint and at campaign end. It prints every page or component that no
list file names; an empty result means the checklist is complete.

```bash
L=Memory/campaigns/contractor-design-concept/stages
{ find src/routes -name '+page.svelte' | sed 's|^src/routes/||;s|/\?+page.svelte$||;s|^$|/|';
  find src/lib/components -name '*.svelte' | sed 's|^src/lib/components/||;s|\.svelte$||'; } |
  sort -u | while read -r p; do grep -rqF -- "\`$p\`" "$L" || echo "MISSING $p"; done
```

On 2026-10-18 it lists 670 pieces: 139 pages and 531 components.

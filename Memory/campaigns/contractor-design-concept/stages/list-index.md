# Redesign checklist — index

**Plan:** `docs/contractor-design-concept-behavior-contract.md` § First version 3. Every page and component of the
app is on a list file below, most necessary first. Each piece carries a Pencil tick and a Built tick.

## Key

`| Piece | File | Inside it (pop-ups, tabs, menus, states, role views) | Pencil | Built |`

- Pencil: ⬜ not drawn · 🟡 drawn, waiting for Jafar · ✅ approved · 🔁 *pattern* (follows that pattern's approval)
- Built: ⬜ not built · 🟡 built, being checked · ✅ built and matches Pencil
- ➖ not redesigned, with the reason (tables keep today's look: Jafar 2026-10-17)

**Write each piece in backticks, exactly as the coverage command prints it:**
- Pages are relative to `src/routes`, with no `+page.svelte`, for example `` `(app)/jobs/[id=uuid]` `` (the root
  page is `` `/` ``).
- Components are relative to `src/lib/components`, with no `.svelte`, for example `` `ui/Card` ``.

**Tick rule:** every part that draws or builds a piece updates its tick in the same commit. Built ✅ comes with the
Pencil tidy-up in `docs/pencil-workflow.md` step 6.

## List files

| Tier | File | Covers | Pieces | Pencil ✅ | Built ✅ |
| --- | --- | --- | --- | --- | --- |
| 1 | `list-1-parts.md` | Shared parts and pop-up patterns; left-out pieces with reasons | — | — | — |
| 2 | `list-2-daily.md` | Daily pages, with their record and "new" pages | — | — | — |
| 3 | `list-3-customers-see.md` | Customer pages, customer emails, login and sign-up | — | — | — |
| 4 | `list-4-weekly.md` | The remaining staff work pages | — | — | — |
| 5 | `list-5-growth.md` | Marketing, Reviews, Reports | — | — | — |
| 6 | `list-6-setup-once.md` | Settings and Setup | — | — | — |
| 7 | `list-7-jafar-panel.md` | Jafar's admin panel | — | — | — |

Not made yet: `parts/c5a-redesign-checklist.md` makes them. Split a file that passes 800 words (`list-2a`,
`list-2b`) and give each split its own row.

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

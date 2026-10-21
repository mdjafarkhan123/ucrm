# Type sweep — typed-in font sizes to the variables (2026-10-21)

301 `font-size: <number>px|rem` lines in 100 files under `src` now use `var(--typography--fontSize-…)`
(Jafar's table, `typography.md`); no new tokens. Rules used: 9–11 → `-overline` (12), never under 12; 12 → `-small`
(14) for dates, meta and pills, `-overline` (12) for uppercase group and table labels and avatar initials; 13 →
`-base`, `-label` or `-small` by role; 15–18 → `-large`; 20–22 → `-larger`; 24–26 → `-largest`; 28 → `-display`;
32–34 → `-stat`; 36–40 → `-jumbo`; 48–52 → `-extravagant`. The login title is
`clamp(-display, 5vw, -jumbo)`.

## Kept on purpose

- Three Botanical theme files (18 lines): Jafar's "Classic only" rule.
- Emails (`src/lib/server/**`, inline `font-size:13px`) and the website chat widget (`src/widget/website-chat.ts`):
  they run outside the app's stylesheet, so the variables cannot reach them. The widget's four 11px lines (footer,
  day divider, message time, retry link) are now 12px, Jafar's yes, same day.
- `KpiCard` and `SupportConversation` already mix variables inside `clamp`/`max`.

## Checked

Playwright (Chromium), contractor owner from `Login.md`, `localhost:5173` (Jafar's server), **1440 × 900**:
Home, Jobs, Schedule (week, month, day, Unscheduled drawer), Clients, Requests, Quotes, Invoices, Inbox,
Settings, Team, Communication Balance, and a job, client, quote, invoice and request record page; the
notification pop-up; the New request form; Home, a job, Inbox, Schedule and Balance in dark mode.

- No page scrolls sideways.
- Text that ends in "…" or is clipped was listed for every page: it is screen-reader-only text, or long emails,
  street addresses and message previews that end in "…" by design.
- Follow-up, Jafar's yes the same day: the sidebar line "Workspace · O…" was cut off on every page since the
  table made `-small` 14px (it needs 131px and has 116). It now wraps ("Workspace ·" / "Owner"; "Workspace ·" /
  "Administrator"), the dot kept with "Workspace" (`Sidebar.svelte`). Checked live at 1440, light, dark and collapsed:
  `sidebar-owner-after.png`, `sidebar-administrator-after.png`. The Botanical sidebar is not changed.
- Pencil: 393 typed-in text sizes in `concept.pen` bound to the variables (see `parts/type-sweep.md`).

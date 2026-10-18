# Colour Tokens

> Dependencies: none. Each colour family has three tokens: main (icons, dots, lines), `--surface` (tile and
> pill background), `--onSurface` (text on the surface).

## Base

| Token | Use |
|---|---|
| `--color-surface--background` | Page background |
| `--color-surface` | Cards, sidebar, menus, fields |
| `--color-surface--background--subtle` | Table header row |
| `--color-surface--hover` | Row and menu-item hover |
| `--color-surface--active` | Current page in the sidebar |
| `--color-border` | Card and divider edges |
| `--color-border--interactive` | Field and secondary-button edges |
| `--color-heading` | Titles and numbers |
| `--color-text` | Body text |
| `--color-text--secondary` | Labels, dates, hints |
| `--color-icon` / `--color-icon--secondary` | Neutral icons / quiet icons |

## Record Colours

| Record | Token family | Tile icon |
|---|---|---|
| Request | `--color-request` (orange) | inbox |
| Quote | `--color-quote` (pink) | file-text |
| Job, Visit | `--color-job` (green) | hammer |
| Invoice, Payment | `--color-invoice` (blue) | receipt, credit-card |
| Client | `--color-client` (taupe) | user-round |
| Task | `--color-task` | square-check |
| Event | `--color-event` (yellow; tile icon uses `--onSurface`) | calendar-days |

## Section Colours (new in the concept)

| Section | Token family | Pages | Light main / surface | Dark main / surface |
|---|---|---|---|---|
| Time | `--color-time` | Schedule, Timesheets | `#556acb` / `#e6e9f7` | `#8897db` / `#374584` |
| Conversation | `--color-conversation` | Inbox | `#118197` / `#def3f7` | `#59c4d9` / `#0b414c` |
| Growth | `--color-growth` | Pipeline, Marketing, Reports | `#5b40bf` / `#ebe8f7` | `#9987d9` / `#3e2b82` |
| Review | `--color-review` | Reviews | `#86761d` / `#f5f0d1` | `#cdb52d` / `#645916` |
| Your business | `--color-inactive` | Home, Files, Settings | existing | existing |

They are in `concept.pen`; add them to `_variables.scss` with the first screen that uses them.

## Feature Card Colours

One deep-green card per screen at most (Home's Today card; the money card beside a list's overview and on
client and invoice pages). The same in light and dark mode.

| Token | Value | Use |
|---|---|---|
| `--color-feature--start` / `--end` | green 800 `#02532d` → green 700 `#037741` | Card gradient |
| `--color-feature--glow` / `--glow-end` | white 12% → 0% | Soft light in the top-right corner |
| `--color-feature--text` | white | Titles and figures |
| `--color-feature--text--secondary` | white 72% | Date, summary, hints |
| `--color-feature--subtle` | white 10% | Panels and tiles inside the card |
| `--color-feature--border` | white 18% | Edges of those panels |
| `--color-feature--alert` | red 400 `#e9a29b` | Overdue part of a bar on the card (status reds vanish on green) |

## Status Colours

| Meaning | Token family | Examples |
|---|---|---|
| Done | `--color-success` | Paid, Completed, Approved |
| Waiting | `--color-warning` | Awaiting reply, Unscheduled |
| Act now | `--color-critical` | Overdue, Failed, Late |
| Planned | `--color-informative` | Scheduled, Sent, Upcoming |
| Draft or archived | `--color-inactive` | Draft, Archived, Cancelled |

## Rules

- A record keeps its colour everywhere: tile, pill, schedule line.

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
| `--color-surface--key` | White button (raised key); `--key-hover` and `--key-pressed` for its states |
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
| Client | `--color-client` (sand) | user-round |
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
client pages). Job, quote and invoice pages use the money summary card instead (Money Card Colours below). The same in light and dark mode.

| Token | Value | Use |
|---|---|---|
| `--color-feature--start` / `--end` | green 800 `#02532d` → green 700 `#037741` | Card gradient |
| `--color-feature--glow` / `--glow-end` | white 12% → 0% | Soft light in the top-right corner |
| `--color-feature--text` | white | Titles and figures |
| `--color-feature--text--secondary` | white 72% | Date, summary, hints |
| `--color-feature--subtle` | white 10% | Panels and tiles inside the card |
| `--color-feature--border` | white 18% | Edges of those panels |
| `--color-feature--alert` | red 400 `#e9a29b` | Overdue part of a bar on the card (status reds vanish on green) |
| `--color-feature--items` | pink 400 `#d5aab2` | Item cost on a profit bar (items were priced on the quote) |
| `--color-feature--labor` | indigo light `#8897db` | Labour cost on a profit bar (time colour) |
| `--color-feature--expenses` | light blue 400 `#73bcf7` | Expenses on a profit bar (money paid out) |

A profit bar on the card shows each cost in its colour and the profit in white, 10px tall, 3px between parts.

## Money Card Colours

The shared money summary card on job, quote and invoice pages (Pencil: board "Concept · Batch 35 · Shared money
summary card · Approved B", approved 2026-10-21). The same in light and dark mode. Each colour means one thing.

| Token | Value | Use |
|---|---|---|
| `--color-money--start` / `--end` | `#032b3a` → `#0b4559` | Card gradient (ink blue) |
| `--color-money--border` | white 18% | Card edge, so it stays visible on the dark page |
| `--color-money--items` | cyan `#22d3ee` | Item cost on the bar (materials and products on the lines) |
| `--color-money--expenses` | orange `#fb923c` | Expenses (money paid out) |
| `--color-money--labor` | violet `#a78bfa` | Labour (crew time) |
| `--color-money--profit` | green `#4ade80` | Profit: bar, profit amounts, margin pill fill |
| `--color-money--loss` | red `#f43f5e` | Loss: bar, loss figure, "Losing money" pill fill |
| `--color-money--warning` | yellow `#facc15` | "Below target" pill only, never a bar part |

Bar order: item cost · expenses · labour · profit (or loss). Pills on profit, loss and warning fills use
`--color-money--start` text. Other figures and labels stay white or white 72%.

## Photo Studio Colour

| Token | Value | Use |
|---|---|---|
| `--color-photo-studio` | `#032b3a`, the same in light and dark | The dark panel a photo sits on in the profile photo pop-up (`modals.md`), so a photo and its white words read the same in both modes |

In `concept.pen`; add it to `_variables.scss` with the build.

## Channel Colours

The marks that tell channels apart in the inbox (`inbox.md`), the same in light and dark. In `concept.pen`; add the
three tile colours to `_variables.scss` with the inbox build.

| Token | Value | Use |
|---|---|---|
| `--color-messenger` | `#0866FF` | Facebook Messenger's own logo, the one brand mark in the app: Settings → Messenger, a Page's badge, Messenger marks in the inbox. Never for anything else |
| `--color-channel-email` | `#E4702A` | Email tile |
| `--color-channel-text` | `#118197` | Text tile |
| `--color-channel-chat` | `#6B4BD8` | Website chat tile |

## File Families

Only on a document's type tab (`files.md`), approved 2026-10-19. Photos show as photos.

| Family | Token | Files |
|---|---|---|
| Documents | `--color-informative` | PDF, Word, text |
| Spreadsheets | `--color-success` | Excel, CSV |
| Videos | `--color-growth` | MP4, MOV |
| Anything else | `--color-inactive` | Other files |

## Status Colours

| Meaning | Token family | Examples |
|---|---|---|
| Done | `--color-success` | Paid, Completed, Approved |
| Waiting | `--color-warning` | Awaiting reply, Unscheduled |
| Act now | `--color-critical` | Overdue, Failed, Late |
| Planned | `--color-informative` | Scheduled, Sent, Upcoming |
| Draft or archived | `--color-inactive` | Draft, Archived, Cancelled |

## Client colour (changed 2026-10-21)

The old taupe surface was the page colour in light mode and the subtle grey in dark mode, so a client header
blended into the page (Jafar, 2026-10-21). New values, in `concept.pen`; put them in `_variables.scss` with the build:

| Token | Light | Dark |
|---|---|---|
| `--color-client` | `#8a6a4b` | `#cfae88` |
| `--color-client--surface` | `#e8dbc8` | `#4a3d2f` |
| `--color-client--surface-edge` | `#d6c4aa` | `#5e4e3c` |
| `--color-client--onSurface` | `#4a3826` | `#efe3d2` |

## Rules

- A record keeps its colour everywhere: tile, pill, schedule line.

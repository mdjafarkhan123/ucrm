# Campaign Memory Index

## Default current

`sales-pipeline`. Part 1 closed 2026-08-19. Part 2 (ownership, value, dates, sort/filter bar) is active:
items 1 through 5 shipped and verified 2026-08-19 — owner, value and dates persist behind a single gated
write path, money is locked away from members at the database, `pipeline_board_page` is the board's one
read with a sort-aware keyset cursor proved on 50,000 rows, the summary counts and totals the same filtered
set in one read, and the board now has its control bar with every filter and sort held in the URL. Resume at
item 6, the card's ownership action — which also adds Part 2's first write route — from
`Memory/campaigns/sales-pipeline/NOW.md` and its Part 2 packet.
`list-column-sorting` closed 2026-08-18 (click-to-sort on Clients and Requests, browser-verified, including a
title containing a literal quote). `requests-and-assessments` closed 2026-08-18 with its approved staff
workflow browser-verified; `clients-properties` closed 2026-08-18.

## Campaigns

| Campaign | Status | Purpose | Checkpoint | Read when |
| --- | --- | --- | --- | --- |
| `sales-pipeline` | Part 2 active and approved | Build one protected Request-to-Quote commercial lifecycle board with automatic Opportunity identity and separate outcomes. | `Memory/campaigns/sales-pipeline/NOW.md` | Work touches Opportunities, Pipeline stages, sales outcomes, or Request/Quote commercial continuity. |
| `communications` | Paused at approved contract | Build contractor Communications through independently gated email and Twilio channel tracks over one shared Conversations model. | `Memory/campaigns/communications/NOW.md` | Work touches email, SMS, conversations, or the client Communication tab. Clients and Properties, its old prerequisite, is done. |
| `jafar-panel` | Paused pending contractor subsystem | Finish the Platform Owner journey from application through organization closure and provider controls. | `Memory/campaigns/jafar-panel/NOW.md` | Work resumes a dependency-linked Platform Owner control or the user names the Jafar panel campaign. |
| `data-cache-architecture` | Paused | Establish safe TanStack Query ownership, shared keys, hydration, and targeted invalidation. | `Memory/campaigns/data-cache-architecture/NOW.md` | Work touches query ownership, SSR hydration, cached navigation, invalidation conventions, or Realtime cache updates. |
| `operations-prospects-ux` | Paused by explicit deferral | Finish the dedicated Prospect detail experience after the completed Operations dialog work. | `Memory/campaigns/operations-prospects-ux/NOW.md` | The user explicitly resumes the Prospect detail-page work. |

## Deferred work

Read `Memory/deferred/INDEX.md` only when a campaign checkpoint points there or the user asks about deferred work.

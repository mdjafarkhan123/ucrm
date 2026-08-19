# Sales Pipeline Roadmap

| Part | Outcome | Status | Dependencies | Packet | Completion gate |
| --- | --- | --- | --- | --- | --- |
| 1 | Request-side Opportunity foundation and first protected board | Closed 2026-08-19 | Requests and Assessments complete | `parts/01-request-side-foundation.md` | Existing and new Requests appear exactly once; tenant isolation, access, and the desktop board pass database/API/browser/accessibility checks. |
| 2 | Ownership, value, dates, and the sort/filter bar | Closed 2026-08-19 | 1 | `parts/02-ownership-value-dates-sort-filter.md` | Staff can find and maintain accountable open work without Pipeline state contradicting Request truth. Money appears on cards and column headers only once a real value exists. |
| 3 | Actionable Opportunity Brief: Tasks and Notes | Closed 2026-08-19 | 1, 2 | `parts/03-opportunity-brief-tasks-notes.md` | Staff can manage accountable follow-up and deal context from the drawer without losing their place on the board. Part 1's thin drawer grows rather than being replaced. |
| 4 | Won, Lost, reopen, and sales outcomes | Closed 2026-08-19 | 1–3 | `parts/04-won-lost-reopen-outcomes.md` | Outcome transitions are atomic, reasoned, permission-safe, idempotent, and preserved in history/reporting. |
| 5 | Protected Quote stages, drag with required actions, and automatic Won | Blocked on Quotes | 1–4 and Quotes domain | Create after Quotes behavior is approved | A converted Request leaves the Request stages and its Quote appears in Draft as its own card; forward drag performs the real action first; approving a Quote wins it atomically. |
| 6 | Final A–Z audit and contractor manual | Pending | 1–5 | Create when active | Desktop, accessibility, performance, and security gates pass and the product manual reflects the shipped journey. |

## Standing decisions (updated 2026-08-19)

Jobber's current Sales Pipeline is the reference. The earlier UCRM opportunity model is overridden wherever
the two disagree. See `docs/sales-pipeline-behavior-contract.md` for the full text; the load-bearing ones:

- No standalone Opportunities. They come only from Requests and, later, Quotes.
- Request and Quote are separate cards. A converted Request leaves the board; its Quote enters Draft.
- Desktop only. Mobile is a separate app, later, and is out of this campaign entirely.
- Dragging is Part 5, once both groups exist. Part 1 cards must not look draggable.

## Sequencing notes

- Parts 1 through 4 use the fixed Request-side subset of the seven protected stages.
- Custom stage creation, renaming, deletion, and reordering are deliberately outside the first release. Add them
  only after real contractor feedback establishes the need.
- Part 5 creates no placeholder dependency. When Parts 1 through 4 close, pause this campaign, run the Quotes
  campaign far enough to establish Quote truth, then resume Part 5.
- Jobs remain outside the active Pipeline. A Job makes Won terminal when Jobs later supplies that relationship.
- Part 1 ships no money, no sort or filter bar, and no lead source. Each arrives with the part that gives it
  real data, so the board never shows a placeholder.
- Part 3 is split into independently verified Task foundation, Task UI, and Notes subparts. Its embedded
  activity timeline and Task Schedule UI are explicit deferrals, not incomplete acceptance conditions.
- Part 4 is split into 4A (database engine), 4B (Lost/Reopen actions), and 4C (Sales Outcomes tiles/report),
  all closed 2026-08-19. 4A also closed a pre-existing bug: the Request detail page's plain Archive toggle
  bypassed the outcome model; see the 4A packet for what changed. 4B found that `SidePanel` is a true modal —
  the board is not interactive behind an open Brief — see the 4B packet.
- Part 4 is now closed. Per the note above, this campaign pauses here: Part 5 has no placeholder dependency,
  so resume it only once the Quotes campaign has run far enough to establish real Quote truth.

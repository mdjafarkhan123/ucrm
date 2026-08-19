# Sales Pipeline Roadmap

| Part | Outcome | Status | Dependencies | Packet | Completion gate |
| --- | --- | --- | --- | --- | --- |
| 1 | Request-side Opportunity foundation and first protected board | Closed 2026-08-19 | Requests and Assessments complete | `parts/01-request-side-foundation.md` | Existing and new Requests appear exactly once; tenant isolation, access, and the desktop board pass database/API/browser/accessibility checks. |
| 2 | Ownership, value, dates, and the sort/filter bar | Active, approved 2026-08-19 | 1 | `parts/02-ownership-value-dates-sort-filter.md` | Staff can find and maintain accountable open work without Pipeline state contradicting Request truth. Money appears on cards and column headers only once a real value exists. |
| 3 | Full Opportunity brief: notes, tasks, and activity | Pending | 1, 2 | Create when active | Staff can act on a card from the drawer without losing their place on the board. Part 1's thin drawer grows here rather than being replaced. |
| 4 | Won, Lost, reopen, and sales outcomes | Pending | 1–3 | Create when active | Outcome transitions are atomic, reasoned, permission-safe, idempotent, and preserved in history/reporting. |
| 5 | Protected Quote stages, drag with required actions, and automatic Won | Blocked on Quotes | 1–4 and Quotes domain | Create after Quotes behavior is approved | A converted Request leaves the Request stages and its Quote appears in Draft as its own card; forward drag performs the real action first; approving a Quote wins it atomically. |
| 6 | Final A–Z audit and contractor manual | Pending | 1–5 | Create when active | Desktop, accessibility, performance, and security gates pass and the product manual reflects the shipped journey. |

## Standing decisions (2026-08-18)

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

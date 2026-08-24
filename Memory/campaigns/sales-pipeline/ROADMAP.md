# Sales Pipeline Roadmap

| Part | Outcome | Status | Dependencies | Packet | Completion gate |
| --- | --- | --- | --- | --- | --- |
| 1 | Request-side Opportunity foundation and first protected board | Closed 2026-08-19 | Requests and Assessments complete | `parts/01-request-side-foundation.md` | Existing and new Requests appear exactly once; tenant isolation, access, and the desktop board pass database/API/browser/accessibility checks. |
| 2 | Ownership, value, dates, and the sort/filter bar | Closed 2026-08-19 | 1 | `parts/02-ownership-value-dates-sort-filter.md` | Staff can find and maintain accountable open work without Pipeline state contradicting Request truth. Money appears on cards and column headers only once a real value exists. |
| 3 | Actionable Opportunity Brief: Tasks and Notes | Closed 2026-08-19 | 1, 2 | `parts/03-opportunity-brief-tasks-notes.md` | Staff can manage accountable follow-up and deal context from the drawer without losing their place on the board. Part 1's thin drawer grows rather than being replaced. |
| 4 | Won, Lost, reopen, and sales outcomes | Closed 2026-08-19 | 1–3 | `parts/04-won-lost-reopen-outcomes.md` | Outcome transitions are atomic, reasoned, permission-safe, idempotent, and preserved in history/reporting. |
| 5 | Protected Quote stages, drag with required actions, and automatic Won | In progress — 5A started 2026-08-23 | 1–4 and Quotes domain (Parts 1-6 closed) | See subparts | A converted Request leaves the Request stages and its Quote appears in Draft as its own card; forward drag performs the real action first; approving a Quote wins it atomically. |
| 5A | Quote-backed Opportunity identity and automatic outcomes | Closed 2026-08-23 | 1–4, Quotes 1-6 | `parts/05a-quote-opportunity-identity-and-outcomes.md` | A Quote gets its own Opportunity (direct or Request-converted); Approve/Decline/Revise-reopen/Begin-material-revision atomically drive Won/Lost/Reopen; archiving a still-open Quote (the Quote's own command, no new RPC) is how a stale Draft/Awaiting/Changes-requested quote gets marked Lost. Database only, pgTAP-verified (28 assertions), performance-reviewed (one seq-scan bug caught and fixed). |
| 5B | Forward-only drag with required action | Closed 2026-08-23 | 5A | `parts/05b-drag-and-move-api.md` | Dropping a card into a protected stage performs that stage's real domain command first; the card moves only on success. Database only performs a read-only permission/transition gate (the table grants no other read); pgTAP 17/17, vitest 15/15, performance-reviewed. |
| 5C-i | Quotes board read model + column rendering (no drag) | Closed 2026-08-23 | 5A-5B | `parts/05c-i-quotes-board-read-model.md` | The board's two reads answer for Quote stages; the Quotes column group renders real cards on `/pipeline`; browser-verified against real data. |
| 5C-ii | Drag gesture for both groups | Closed 2026-08-23 | 5C-i | `parts/05c-ii-drag-gesture.md` | `svelte-dnd-action` wired to the protected action; refused drops stay client-only; valid drops show saving feedback and move only after server-confirmed refresh; full-height zones and every transition pass live verification. |
| 5C-iii | Unified board and Pipeline presentation setting | Closed 2026-08-24 | 5C-ii | `parts/05c-iii-unified-board-and-settings.md` | Requests and Quotes form one horizontally scrolling journey; five columns are the default; Settings can expand Assessment into its three protected stages without changing workflow truth. |
| 5D | Accidental-drag recovery (Undo) | **Cut 2026-08-24 — Jafar decided this isn't needed.** | — | — | — |
| 6 | Final A–Z audit and contractor manual | Pending | 1–5C-iii | Create when active | Desktop, accessibility, performance, and security gates pass and the product manual reflects the shipped journey. |

## Standing decisions (updated 2026-08-19)

Jobber's current Sales Pipeline is the reference. The earlier UCRM opportunity model is overridden wherever
the two disagree. See `docs/sales-pipeline-behavior-contract.md` for the full text; the load-bearing ones:

- No standalone Opportunities. They come only from Requests and, later, Quotes.
- Request and Quote are separate cards. A converted Request leaves the board; its Quote enters Draft.
- Desktop only. Mobile is a separate app, later, and is out of this campaign entirely.
- Dragging is Part 5, once both groups exist. Part 1 cards must not look draggable.

## Sequencing notes

- Parts 1 through 4 use the fixed Request-side subset of the seven protected underlying stages. Part 5C-iii
  changes their presentation, not their stored meaning.
- Custom follow-up stages are deliberately outside the first release. Industry rules and the approved future
  guardrails live in `docs/research/pipeline-stage-customization-industry-reference.md` and the behavior
  contract; no custom-stage controls are placeholders in 5C-iii.
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
- Part 4 is now closed. Quotes Parts 1-6 closed 2026-08-22, establishing real Quote/deposit truth, so Part 5
  resumed 2026-08-23. It is split into 5A (database), 5B (drag/API), 5C (board UI) — same pattern as Part 4.
  5C itself split further into 5C-i (read model + rendering) and 5C-ii (drag gesture), approved 2026-08-23,
  because attempting the read-model migration, the API/type widening, the rendering, the drag gesture, and
  the schedule dialog in one session would have materially reduced review quality.
- Decline-Lost/Reopen automation for Quotes is trigger-based (mirrors Request-side stage derivation), not a
  new client-facing RPC: no idempotency key needed since it fires inside the same DB transaction as the
  Quote command, unlike the existing manual Lost/Reopen RPCs which stay for abandoning a still-open Quote.
  See `parts/05a-quote-opportunity-identity-and-outcomes.md` for the full design and why.
- 5B's drag endpoint refuses more than Jobber's own "backward is refused" rule literally requires: Changes
  requested's two real exits (Revise, Republish) are backward on the board, so neither is a drag target —
  both stay Quote-page actions, confirmed with Jafar 2026-08-23. See `parts/05b-drag-and-move-api.md`.
- 5C-i's browser verification (2026-08-23) found every Quote card/column money total blank: nothing ever
  wrote `estimated_value` for a quote-backed opportunity. Fixed same session — see the 5C-i packet's
  "Value sync fix" section. Open, unrelated to 5C-i: `/pipeline` stacks Requests above Quotes in two
  separate sections; Jobber puts both groups side by side in one board split by a vertical divider
  (`jobber-02-requests-leads.md` §4.6.1). Jafar resolved this on 2026-08-24: 5C-iii will make one horizontal
  board with five visible columns by default and an optional detailed Assessment view.
- 5C-iii's design was approved 2026-08-24 with eight corrections from Jafar (named logical column instead of
  an arbitrary stage list, cursor bound to the column, appointment in the grouped read, the collapsed view
  staying actionable through the Brief, a designed Request-to-Draft conversion boundary, `organization_settings`
  as the store, an honestly-invalidated read path, and indexes decided by measurement). All eight are recorded
  in its packet. Measurement then contradicted two of the packet's own draft assumptions and both were
  corrected there rather than left standing: a Sort node does not break keyset correctness (only speed), and
  every non-default sort — not just the grouped default — reads without an ordered index. Only the default
  sort got a group index, following `opportunities_board_owner_idx`'s precedent, with the measured cost of the
  others recorded and a revisit trigger.
- Regenerating `src/lib/database.types.ts` on 2026-08-24 took `npm run check` from four Team/Profile errors to
  **0 errors**. Those errors were recorded in the 5C-ii packet as unrelated pre-existing failures; they were
  actually caused by the types file being stale against the live schema.
- 5C-ii's browser verification found and fixed the native-button drag blocker. Jafar then found the short
  drop-zone gap and a refused-drop disappearance. Both are fixed in code. Jafar approved server-confirmed
  placement plus persistent Saving/Saved toast feedback on 2026-08-23. Jafar directly verified all five live
  checks (refused/backward snap-back, forward drop saving/saved feedback, schedule-dialog drop, full-height
  empty-space drop in both groups, full transition table) on 2026-08-23 and confirmed all pass. 5C-ii is
  closed.
- 5C-iii's browser verification: Jafar verified both UI slices live on 2026-08-24 and confirmed every
  acceptance check in the packet passes. 5C-iii is closed.
- Part 5D (accidental-drag Undo) is cut, 2026-08-24 — Jafar decided it isn't needed. Request-to-Draft
  conversion's confirm-before-commit, no-Undo behavior (from 5C-iii's "Conversion boundary") stands as
  permanent behavior on its own; it no longer needs a 5D to inherit it. Part 6 now depends on 1–5C-iii only.

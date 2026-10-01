# Pipeline gap audit: UCRM against Jobber and the wider leaders

Researched 2026-10-01 for the `pipeline-upgrade` campaign. Compares the built Pipeline and its plan
(`docs/sales-pipeline-behavior-contract.md`) with Jobber's current Sales Pipeline, Pipedrive, HubSpot, and
Housecall Pro. Jafar's instruction for this campaign: fix every problem, fill every gap, match the leaders
where UCRM has its own habit, and improve on them where it clearly helps. No product code was changed.

## Verdict

The Pipeline follows the contractor-industry standard: it is Jobber's model (system-driven columns, forward-only
moves, Won/Lost outside the board, the board stops at the quote). The gaps are listed below; each one is either
settled by Jafar's "match the leaders" instruction or is an open choice in the plan's **Still unclear** list.

## A. Problems found in the built Pipeline

| # | Problem | Evidence | Leader behavior |
| --- | --- | --- | --- |
| A1 | Dragging a Draft quote to Awaiting response only marks it as sent; the customer receives nothing and no follow-up starts | The drop runs the same command as the Quote page's "Mark as awaiting response"; quote follow-ups start only when a quote is actually delivered | Jobber: the drop "prompts you to view and send the quote (either via email or text message), or mark the quote as 'Awaiting Response'" |
| A2 | A request cannot become a job, so a small job can only reach Won through a quote | Request page "Convert to job" is disabled; only quote approval writes Won, although the plan says a job also makes Won | Jobber: Won when "a quote is approved, or a job is created" |
| A3 | Every card turns red 24 hours after the clock starts, whatever the column | Copied Jobber's fixed 1 h / 24 h rule | Pipedrive: each stage has its own "rotting" days, counted from the last activity on the deal; doing something on the deal resets it |
| A4 | No custom columns | Plan deferred them to "a later release" | Jobber (up to 25), Housecall Pro, Pipedrive, and HubSpot all allow them |
| A5 | Blocked moves still fall back to "That card could not be moved"; only Assessment cards have a non-drag next step | Brief next action exists for the three Assessment states only | WCAG 2.2 needs a non-drag way to move; Salesforce/Pipedrive offer a stage control beside dragging; see `pipeline-blocked-moves-2026-09-21.md` |

## B. Missing compared with Jobber

| # | Jobber has | UCRM today |
| --- | --- | --- |
| B1 | A search box to find a card | No search |
| B2 | Mark a quote card Lost from the board (not Drafts); archives the quote, optional reason | Quote cards have no Mark as lost; a quote becomes Lost only by Decline/archive on the Quote page, with no reason |
| B3 | Tasks with a due date appear on the assignee's Schedule | Tasks stay inside the Brief |
| B4 | @mention a teammate in a note | Not available anywhere in UCRM notes |
| B5 | Photos on notes (screenshots, Aug 2026) | Notes are text only (Files & Media now exists) |
| B6 | An Email quick action in the Brief (screenshots) | View request / View quote only |
| B7 | Lead source chip on cards and a lead-source filter (screenshots; the Sep 2026 article no longer mentions it) | Not shown, although clients already store a lead source |
| B8 | A global "+ Add new" create button on the board | None |
| B9 | AI opportunity summary (Aug 2026 screenshots only; the current article does not mention it) | None |

## C. UCRM habits the leaders do not share

| # | UCRM habit | Leaders | Status |
| --- | --- | --- | --- |
| C1 | Assessment folded into one column by default, with a switch to show three | Jobber always shows seven columns | Open choice |
| C2 | A separate "Next follow-up" date beside Tasks | Jobber and Pipedrive use the next open task/activity; no separate field | Open choice |
| C3 | An "Expected close date" field that nothing uses | HubSpot and Pipedrive have it; Jobber does not | Open choice |
| C4 | The page scrolls and each column has a "Load more" button | Jobber, HubSpot, and Trello-style boards scroll each column on its own | Open choice |
| C5 | Desktop only | Jobber's app has no pipeline; HubSpot's phone app has a deals board with tap-to-move | Open choice (reverses an earlier decision) |
| C6 | A fixed list of seven lost reasons | Pipedrive: admins define the list and may allow free text; HubSpot: a "Closed lost reason" field | Open choice |
| C7 | A declined quote becomes Lost with no reason | Housecall Pro shows Rejected estimates; no reason is captured in UCRM | Small improvement proposed |
| C8 | Read-only Pipeline role, reasoned reopen of Lost, no `$0.00` placeholders | Pipedrive and HubSpot allow reopening; read-only access is common | Keep: improvements |

## D. Improvements seen at the wider leaders

- **Reports:** HubSpot and Pipedrive report lost reasons, stage-to-stage conversion, and time to close; Jobber's
  Sales Outcomes report lists Won/Lost records only.
- **Text and Call buttons** beside Email (Housecall Pro's lead handling).
- **Task assignment notifications** (HubSpot and Pipedrive notify task owners).
- **AI summaries** (HubSpot) — costs per use and sends customer data to an AI provider, so it needs Jafar's
  decision for EU/UK customers.

## Already matching the leaders

System-owned columns and entry rules; automatic movement; forward-only drag with the real action; Won on quote
approval; Lost by hand with an optional reason that archives the record; Won/Lost tiles for the past 30 days;
the Sales Outcomes report; salesperson and date filters; sort by time in stage, created date, or value; the
Brief drawer with Tasks (five open, five completed) and Notes; the board stops at the quote.

## Sources

- Jobber, [Sales Pipeline](https://help.getjobber.com/en/articles/sales-pipeline/) — updated 2026-09-25; drag
  prompts, Won/Lost, search, Schedule tasks, mentions, freshness.
- Jafar's Jobber screenshots `Design/pipeline/1.webp`–`16.webp`, summarized in
  `.claude/skills/jobber/jobber-02-requests-leads.md` §4.6.1.
- Pipedrive, [The Rotting feature](https://support.pipedrive.com/en/article/the-rotting-feature) — updated
  2026-09-03; per-stage days, inactivity clock, red card.
- Pipedrive, [How can I enable predefined lost reasons?](https://support.pipedrive.com/en/article/how-can-i-enable-predefined-lost-reasons)
- Pipedrive, [Pipeline view](https://support.pipedrive.com/en/article/pipeline-view) — "Move to" and the detail-view
  stage control.
- HubSpot, [Default deal properties](https://knowledge.hubspot.com/properties/hubspots-default-deal-properties),
  [Set up and manage pipelines](https://knowledge.hubspot.com/object-settings/set-up-and-customize-pipelines),
  [Records in the mobile app](https://knowledge.hubspot.com/records/work-with-records-in-the-hubspot-mobile-app).
- Earlier UCRM research: `contractor-crm-sales-pipeline-comparison.md`, `housecall-pro-pipeline-model.md`,
  `pipeline-stage-customization-industry-reference.md`, `pipeline-blocked-moves-2026-09-21.md`.

# Pipeline blocked moves: mature-product research and recommendation

Researched 2026-09-21 for UCRM's contractor pipeline. This note uses first-party documentation from HubSpot, Atlassian Jira, Salesforce, and W3C. It separates documented behavior from the recommendation for UCRM. No product code or live account data was changed.

## Executive finding

The strongest shared pattern is **intent → resolve → commit**:

1. show which destinations are actually available;
2. let a drag or stage menu express where the user wants to go;
3. collect any required information or confirmation before changing the record;
4. commit the transition and its automatic effects only after validation succeeds; and
5. if the transition cannot happen, keep the card where it was and explain the specific reason.

For UCRM, this means using two feedback surfaces, not one universal popup:

- a focused **transition dialog** for a move that is allowed after the contractor supplies information, completes the next prerequisite, or confirms a customer-facing action;
- a concise **status message** for a move that is structurally impossible, belongs to the client, is blocked by permission, or would reverse a history-bearing event.

Silent snap-back and the generic “That card could not be moved” message should both be removed.

## What mature products document

### HubSpot: prevent invalid movement and collect stage requirements in context

- HubSpot supports pipeline rules that prevent skipping stages, prevent backward movement, restrict editing in selected stages, and introduce approval gates. Those rules are enforced across desktop, mobile, and API/integration updates when a user identity is present. [Set up rules for object pipelines](https://knowledge.hubspot.com/object-settings/set-up-pipeline-rules)
- A stage can declare conditional properties, including required properties. When a user creates a record in or moves a record to that stage, HubSpot automatically presents those properties; the record cannot be created or updated until required values exist. [Set up and manage object pipelines](https://knowledge.hubspot.com/object-settings/set-up-and-customize-pipelines)
- From board view, dragging to a stage with required properties leads to a form and a **Next** action. Only after the move succeeds are the board counts, sorting, deal probability, and weighted totals updated. [Manage records in board view](https://knowledge.hubspot.com/records/manage-records-in-board-view)
- Approval is modeled as a real workflow state. The board exposes the approval status and activity; approved work may advance, rejected work is restricted, and moving backward across the approval boundary clears the old approval and requires approval again. [Require approvals for deals](https://knowledge.hubspot.com/object-settings/pipeline-approvals)
- On mobile, users can tap the current stage/status and choose a destination instead of dragging. [Create and manage records in the HubSpot mobile app](https://knowledge.hubspot.com/records/work-with-records-in-the-hubspot-mobile-app)

**Lesson for UCRM:** stage prerequisites belong at the attempted transition, and automatic consequences follow a successful transition. Rules must apply consistently outside the board too.

### Jira: separate availability, validation, and after-transition actions

- Jira runs workflow rules in a clear order: **restrict transition** before an attempt, **validate details** during the attempt, and **perform actions** only after the transition. Restrictions can hide unavailable transitions; validators leave an action visible but stop completion until the problem is corrected. [What are the different workflow rule types?](https://support.atlassian.com/jira-software-cloud/docs/what-are-the-different-workflow-rule-types/)
- A board drop can open a transition dialog containing mandatory fields. Jira also offers the same operation from a status menu and respects workflow permissions, conditions, validations, functions, and notifications. Its current transition UI documents confirmation feedback for both success and failure. [Transition a work item](https://support.atlassian.com/jira-software-cloud/docs/transition-an-issue/)
- Jira transitions are one-way. A backward move exists only when a separate reverse transition is designed; it is not an automatic right to rewrite status history. [Create workflow transitions](https://support.atlassian.com/jira-cloud-administration/docs/create-workflow-transitions/)
- Atlassian's own support documentation treats a card snapping back with no clear explanation as a problem. For a missing transition, Jira displays a warning that identifies the card, requested destination, and workflow/condition category. [Unable to drag and drop issues between columns](https://support.atlassian.com/jira/kb/unable-to-drag-and-drop-issues-between-the-columns-on-the-board/) [Unable to reorder issues on a Kanban board](https://support.atlassian.com/jira/kb/unable-to-drag-and-drop-to-reorder-issues-on-a-kanban-board-in-jira/)

**Lesson for UCRM:** permission, prerequisite validation, and automatic side effects are different phases. Do not run later phases when an earlier phase fails.

### Salesforce: drag is a shortcut, not the only workflow control

- Salesforce lets a user advance an opportunity either by dragging its Kanban card or by choosing a stage on the Sales Path and confirming it. [Move an Opportunity to the Next Stage](https://help.salesforce.com/s/articleView?id=sales.opp_move_next_stage.htm&language=en_US&type=5)
- Its Kanban details panel can expose stage-specific key fields and guidance, and opportunity alerts offer concrete next actions such as creating a task. [Work in a Kanban View](https://help.salesforce.com/s/articleView?id=xcloud.kanban_use.htm&language=en_US&type=5)

**Lesson for UCRM:** provide an explicit stage/action control alongside drag, and make guidance actionable instead of merely describing the blockage.

### W3C: dragging requires equivalent controls and announced results

- WCAG 2.2 requires drag-based functionality to have a single-pointer alternative. W3C's Kanban example recommends a click/tap control or dropdown that selects the destination without dragging. Keyboard access is a separate requirement; keyboard support alone does not satisfy the pointer requirement. [Understanding Dragging Movements](https://www.w3.org/WAI/WCAG22/Understanding/dragging-movements) [Technique G219](https://www.w3.org/WAI/WCAG22/Techniques/general/G219)
- Success, failure, waiting, and error messages that do not move focus must be programmatically exposed so assistive technology announces them. [Understanding Status Messages](https://www.w3.org/WAI/WCAG21/Understanding/status-messages.html)

**Lesson for UCRM:** every card needs a non-drag “Move / next action” route, and every failed or successful move needs accessible feedback.

## Recommended behavior for UCRM

| Situation | During drag | After drop or selection | Data effect |
| --- | --- | --- | --- |
| Allowed, internal, and no information needed | Highlight destination | Move immediately; announce success quietly | Commit once |
| Allowed after required information | Highlight as available | Open a focused transition dialog with only the required fields and a destination-named primary action | Commit only on submit |
| Allowed after one real prerequisite | Mark as “action needed,” not fully available | Open **What's needed** with the reason, one primary next action, and **Open record** as secondary | No stage change until prerequisite and transition succeed |
| Sends to a client, converts a record, collects money, or has another consequential side effect | Mark as “review required” | Open the real review/confirmation surface; do not make the card drop itself the final confirmation | Side effect and transition run only after explicit submit |
| Structurally impossible, client-only, terminal, or forbidden backward transition | Dim without removing the column label; do not present it as a valid drop target | Return card to origin and show a specific non-modal message | No write |
| Permission blocked | Dim/unavailable in both drag and stage menu | Say which capability is missing; offer no action the user cannot perform | No write; server rechecks permission |
| Server/network failure | Preserve the visible source position until success | Explain what failed and whether anything changed; offer **Try again** or **Open record** | Re-fetch authoritative state; prevent duplicate side effects |

### Apply that pattern to the known cases

- **Draft quote → Awaiting response:** open the real **Send quote** review dialog, prefilled with recipient and channel. The primary action is **Send quote**. A drop alone should not silently contact the client.
- **New request → Assessment completed:** do not pretend the assessment happened. Explain that an assessment must be scheduled and completed; offer the next real action that this user's role can perform.
- **Assessment scheduled → Draft quote:** show **Complete assessment** as the primary next action. After completion, continue into the existing create-quote flow with request details carried forward. The pipeline card changes only after the real records reach their valid states.
- **Awaiting response → Changes requested:** keep unavailable because this state records a client action. Message: “Only the client can request changes. Open the quote to edit or resend it.”
- **Changes requested → another column:** guide the contractor to **Review and revise quote**. Do not expose arbitrary status-writing buttons in the blocker.
- **Backward moves:** keep them blocked where the columns represent completed events, sent documents, conversions, or client decisions. If the product supports a legitimate correction, expose a named action such as **Revise quote**, **Resend**, or **Reopen** with its real consequences; do not turn it into a raw backward status write.
- **Quote not ready to send:** the Send quote dialog should name each missing field beside the relevant control. Its error heading should say “Quote isn't ready to send,” not “That card could not be moved.”

## Interaction details that matter

- Preflight the card against every destination when drag starts. Use the same transition decision on the stage menu and on the server, so the UI does not advertise moves the server will reject.
- Keep invalid columns visible for orientation. Combine dimming with a not-allowed cursor/icon and text available on focus; color alone is insufficient.
- A **What's needed** dialog should solve one transition, not become a miniature workflow builder. Show the reason, the next genuine action, and a link to the full record. If several tasks require a full page, list them plainly and send the user there.
- Return keyboard focus to the card after cancellation or failure. After success, move focus with the card or announce its new column.
- Use a card menu or stage button on desktop and mobile. It must expose the same available destinations, prerequisites, permissions, and messages as drag-and-drop.
- Do not optimistically show a completed move before a send/conversion succeeds. For uncertain network outcomes, refresh the record before offering another send so the user cannot accidentally duplicate customer communication.

## Minimal first release

This does not require a configurable workflow engine. The smallest complete upgrade is:

1. one shared transition-decision table for the existing pipeline rules;
2. valid, action-needed, review-required, and unavailable destination visuals;
3. a specific status message for impossible and permission-blocked moves;
4. one reusable transition dialog for prerequisites/required fields, delegating rich work to the existing request or quote page;
5. an explicit Send quote review for Draft → Awaiting response;
6. a non-drag stage/action menu on every card; and
7. action-specific rollback, retry, and accessible announcements.

This follows HubSpot's stage-gate pattern, Jira's restrict → validate → act ordering, Salesforce's drag-plus-explicit-control model, and W3C's input/accessibility requirements while keeping UCRM's scope narrow.

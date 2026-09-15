# SMS in Automation — product proposal

Status: Approved by Jafar, 2026-09-12. Durable behavior is recorded in the Automation and unified-inbox
contracts. No coding is authorized by this approval.

This stage defines what a contractor does and sees when SMS is used in Automation. It preserves the approved
editable, linear 50-step workflow model. Implementation planning comes after the full A2 product plan.

## The smallest useful experience

| Feature | Current HighLevel pattern | Proposed UCRM experience |
| --- | --- | --- |
| Add SMS | Add a **Send SMS** action anywhere in a workflow. The trigger supplies the contact. [1] | Add **Send SMS** as an ordinary customer-message step in any eligible preset or custom workflow. It is not restricted to appointment or review recipes. |
| Write the text | Write directly, insert custom values, or start from an SMS template/snippet. A test SMS is available. [1][2] | Write the text, insert only approved placeholders, or insert an editable saved reply. Show a realistic preview, segment count and estimated cost. Allow an authorized user to send a clearly labelled, normally charged test to their verified team phone. |
| Choose the customer number | Workflow SMS normally uses the contact's primary number. [3] | Send to the customer's current primary SMS-capable number at execution time. Do not let a workflow silently choose another saved number. A missing or ineligible primary number skips the SMS with the reason. |
| Choose the business number | HighLevel supports a workflow default and an action-level From-number override. [3][4] | Default to **Automatic**: continue the customer's established eligible conversation number, otherwise use the organization's eligible default. An authorized contractor may pin the step to another eligible business number. An unattended workflow never guesses from a staff member's assignment. |
| Decide when it sends | Separate Wait actions control delays. One workflow timezone and time window holds communication actions until an allowed period. [1][4][5] | Use Wait steps for every delay; the SMS step has no second scheduling system. The workflow has one optional sending window and timezone choice. Business-wide and recipient-local legal quiet hours remain a stricter non-bypassable guard. |
| Handle a reply | HighLevel offers workflow-wide Stop on Response or a Wait-for-reply step. [4][5] | Keep the already-approved recipe-level behavior: a customer reply pauses later customer messages and alerts the responsible team. Authorized staff choose Resume, Skip next, or Stop. Do not add a separate reply toggle to every SMS step. |
| Understand results | HighLevel shows the message in Conversations and action/error/skip evidence in workflow execution logs, but does not publish one complete workflow-SMS status model. [6][7] | Link the SMS and its automation run. Show scheduled and delivery states in Conversations; show every step outcome and reason in Automation history. Never imply an SMS was read. |

## Normal contractor journey

1. In a preset or custom workflow, add **Send SMS** where the customer message should occur.
2. Write the text or insert a saved reply, then personalize it with approved placeholders such as customer,
   appointment, quote, invoice, or business information that the owning workflow genuinely provides.
3. Review the customer-number rule, business sending number, preview, segment estimate, cost estimate, and any
   required sender or opt-out wording.
4. Add or edit a separate Wait step when a delay is needed. Optionally make the workflow sending window narrower
   than the business and legal limits.
5. Optionally send a real test SMS to the authorized user's verified team number.
6. Save the draft. Activation review shows that SMS is ready, which steps send it, the estimated maximum customer
   messages and cost, timing, and any missing sender, consent, balance, permission, or registration dependency.
7. After activation, open either the customer conversation or the automation enrollment to see the linked result.

Selecting a saved reply copies its text into that step. Later saved-reply edits do not silently rewrite an active
workflow or a draft. This matches the approved email-template safety pattern.

## Timing and quiet hours

- A Wait step answers **how long after the previous event?** The workflow sending window answers **on which days
  and during which hours may this workflow contact people?** The legal/business quiet-hours guard answers **is it
  safe and permitted to text this recipient now?** These remain three visible, separate ideas.
- The contractor may choose the organization timezone or the customer's timezone for the workflow window. If a
  customer timezone is unavailable, show that the organization timezone will be used.
- Reaching an SMS step outside the workflow window or legal/business hours produces **Scheduled for [date, time,
  timezone]**, not Failed. Before release, UCRM rechecks the work outcome, reply, consent, number, sender, balance,
  caps, pauses, and usefulness deadline.
- Editing a workflow creates a new version for new enrollments. It does not silently change the message or timing
  already promised by an existing enrollment.
- There is no per-SMS "send later" control inside the workflow action. One-off scheduled texts belong in
  Conversations; automated timing belongs to Wait and the workflow window.

## What the contractor sees when it does not send

| Visible result | Meaning | Where it appears |
| --- | --- | --- |
| **Waiting** | The enrollment has not reached this SMS step because an earlier Wait or condition is still active. | Automation enrollment/history only. |
| **Scheduled** | The SMS step is due but is waiting for the next permitted send time or another temporary gate before its usefulness deadline. Show the next check/send time and timezone. | Automation enrollment and a linked scheduled item in Conversations. |
| **Queued / Sent / Delivered** | Communications accepted the message, the provider accepted or sent it, and—only when proven—the handset delivery was confirmed. | Conversations, linked back to the workflow run. |
| **Checking send status** | UCRM cannot yet prove whether the provider accepted the message. Do not offer a blind duplicate send. | Conversations and Needs attention when human review becomes necessary. |
| **Skipped** | No SMS should be attempted: for example opt-out, missing eligible customer number, outcome already reached, reply made the follow-up unnecessary, expired reminder, or intentionally skipped enrollment step. Show the exact plain-English reason. | Automation enrollment/history; no fake customer message bubble. |
| **Failed** | A real eligible attempt could not complete, such as provider rejection or an exhausted bounded technical retry. Show the useful reason and correction path. | Automation history/Needs attention and Conversations when a message attempt exists. |

Turning SMS back on, adding balance, or fixing registration never releases a stale backlog automatically. Each
still-scheduled item is rechecked; a skipped or failed SMS remains historical unless an authorized person takes a
deliberate retry action that passes all current checks.

## Scope kept out of Stage 5

- no AI message writer;
- no separate **Manual SMS** task action until Automation's Task action is available and a real contractor need is
  approved;
- no branching, loops, node canvas, bulk retroactive enrollment, or a second SMS scheduler;
- no automated picture/MMS upload in the first Automation SMS slice. Workflow messages may use approved secure
  record links; automated media can follow demonstrated demand;
- no marketing/bulk-message behavior. That belongs to A3 with its own consent, registration, and deliverability
  controls.

## Approved UCRM differences

1. **Sender continuity over staff assignment.** Automatic workflow SMS continues the customer's known eligible
   business number, then falls back to the organization default. HighLevel's published general order can prefer a
   staff-assigned number, but its unattended-workflow identity is unclear. UCRM's rule is more predictable for the
   customer and matches the approved Conversations rule.
2. **Reply pauses instead of silently ending.** HighLevel can remove the contact through Stop on Response. UCRM
   keeps the already-approved pause plus team decision so a reply is not mistaken for a completed contractor
   outcome.
3. **Clear scheduled/skip/failure meanings.** HighLevel documents logs and delivery errors but not one complete
   status model. UCRM uses the small visible vocabulary above and keeps automation execution separate from carrier
   delivery truth.
4. **Verified-team-number tests only.** HighLevel accepts an entered test number. UCRM limits this to the user's
   verified team phone and charges it normally, reducing accidental or non-consensual test traffic.
5. **Text and secure links first.** HighLevel supports workflow media in newer product surfaces. UCRM defers
   automated MMS while manual Conversations keeps the already-approved picture support.

## Sources

1. [HighLevel Workflow Action — Send SMS](https://help.gohighlevel.com/support/solutions/articles/155000002474)
2. [HighLevel SMS Templates/Snippets](https://help.gohighlevel.com/support/solutions/articles/48000981405-sms-templates-snippets-overview)
3. [HighLevel multiple contact numbers](https://help.gohighlevel.com/support/solutions/articles/155000000448-adding-multiple-phone-numbers-for-a-contact) and [From-number selection](https://help.gohighlevel.com/support/solutions/articles/48001152126)
4. [HighLevel Workflow Settings](https://help.gohighlevel.com/support/solutions/articles/48001239875)
5. [HighLevel Workflow Action — Wait](https://help.gohighlevel.com/support/solutions/articles/155000002470/)
6. [HighLevel Workflow Execution Logs](https://help.gohighlevel.com/support/solutions/articles/155000003992-execution-logs-enrolment-history-enhancements)
7. [HighLevel SMS delivery errors](https://help.gohighlevel.com/support/solutions/articles/48001208912)

Full evidence and documentation gaps are recorded in `docs/research/ghl-sms-stage5-automation-behavior.md`.

## Approval recorded

Jafar approved the complete Stage 5 proposal and explicitly repeated the no-overengineering boundary on
2026-09-12. Stage 6 product planning comes next; implementation planning and code still wait until the complete
A2 product plan is approved.

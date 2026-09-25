# Google review campaign — product plan

**Status:** Product behavior agreed with the owner on 2026-09-25. This plan defines what the feature does; it does not authorize application coding.

## Goal

Give contractors a simple, powerful way to ask for reviews after successful work. UCRM sends a polite review request by the contractor's chosen channel (SMS by default), gives the customer a branded feedback journey, directs customers to the contractor's Google review destination where configured, and turns private feedback into a recoverable customer-service task.

HighLevel is the reference for review-request automation, manual sending, request tracking, and configurable retry timing. UCRM keeps the owner's chosen rating page and flexible private-feedback form as its own behavior. See [the official HighLevel research](research/highlevel-review-request-behavior-2026-09-25.md) for the confirmed reference behavior.

## Plain-language customer journey

```text
Contractor completes work
→ UCRM sends the review request by the chosen channel (SMS by default)
→ customer opens the branded UCRM feedback page
→ Review routing off (default): the page shows two clear choices to every customer:
  "Leave a Google review" or "Tell us privately"
→ Review routing on (contractor opt-in): 4–5 stars go to the contractor's Google review
  destination; 1–3 stars go to the contractor's private-feedback form
→ private feedback becomes a recovery item for the contractor's team
```

Every request link, whatever the channel (SMS or email), opens the UCRM feedback page—never Google directly. Review routing is off until the contractor deliberately enables it and accepts UCRM's warning; the 4–5 / 1–3 split is the ready-made starting route once it is on.

## Eligibility and enrolment

- A one-time job enters the normal review-request automation only when it is closed with every Visit completed. A close that removed unfinished Visits is a cancellation and never enrolls; the contractor may still send a manual request (owner decision 2026-09-25).
- A recurring job can use an **after every N completed visits** setting chosen by the contractor. UCRM does not ask after every visit by default. The six-month cooldown always wins, following Jobber: a client already asked in the last six months is skipped at their Nth visit, and becomes eligible again at the first Nth visit after the cooldown ends.
- The automatic request uses the client's main contact for the chosen channel (mobile for SMS, email address for Email). A manual request lets the contractor choose another saved client contact.
- A request is not sent if there is no usable contact for the chosen channel, the job is reopened or cancelled before sending, or the contractor has turned the automation off.
- Activating the automation affects future completed work only. It does not automatically send requests for past jobs; contractors use the manual request action for those.
- UCRM provides **Request a review** on a completed job and on the client page.

## Review-request automation

### Ready-made default

- SMS is the default channel. The contractor can switch the automation to **Email** instead (see Channel choice below).
- The first message sends after the job-completion event at the next configured sending time.
- The default has two gentle reminders on the same channel: three days and five days after the first message.
- The default customer cooldown is one automatic review-request sequence per client every six months. The cooldown applies to the automation only; manual requests are not blocked by it (HighLevel documents no cooldown on manual sends).
- UCRM provides three editable starting styles for each channel (SMS text, and email subject and body): **Friendly**, **Professional**, and **Short**.

### Channel choice

- The contractor chooses one channel for the automation: **SMS** (default) or **Email**. Each manual request can also choose its channel, starting from SMS.
- Only channels that are ready can be picked: SMS needs the organization's texting number to be ready; email needs the organization's sending email to be ready. A channel that is not ready is shown with a short reason and a link to set it up.
- Automatic SMS uses the client's main mobile contact; automatic email uses the client's main email address. If the chosen channel has no usable contact, the request is not sent and the Requests tab shows why.
- **UI reuse:** the channel control reuses the existing channel dropdown `src/lib/components/communications/ComposerChannelMenu.svelte` (extended if needed, not copied), and the message fields reuse the existing automation editors `SmsActionEditor.svelte` and `EmailActionEditor.svelte` in `src/lib/components/settings/automation/`.

### Contractor control

- The contractor can select the message style, edit every message, choose timing, add or remove follow-ups, set the duration, and choose the recurring-job visit frequency.
- The setup displays the full sequence as a readable timeline before activation.
- Following HighLevel, the contractor sets the number of reminders and their interval; UCRM does not enforce a fixed maximum. The default is two reminders (HighLevel notes most teams use 2–3). UCRM warns before activation when a chosen pattern is likely to be overly frequent or harmful to customer goodwill. The contractor can stop or change an active automation at any time.
- Manual requests open a small pre-filled panel: select the client contact, choose the channel (SMS preselected), choose the style, review the message, then choose **Send now** or **Schedule**.
- A manual request follows the same reminder plan as the automation (HighLevel applies its retries to manual requests too). Until reminders exist (Part 4), a manual request sends its first message only (owner decision 2026-09-26).
- If the client was already asked recently, the panel says when and still allows sending (owner decision 2026-09-26).
- From the client page, the panel preselects the client's most recently completed job; the contractor may pick another completed job or **No particular job** (owner decision 2026-09-26).
- **Request a review** appears on closed jobs where work was completed and on active recurring jobs once at least one visit is completed (owner decision 2026-09-26).

### When the sequence stops

- UCRM follows HighLevel's useful pattern: the retry sequence stops after the customer continues to the Google review destination or submits private feedback.
- It also stops when the contractor cancels the request, the message cannot be delivered (SMS failure or email bounce), the customer replies STOP or unsubscribes from email, the customer is no longer eligible, or the job is reopened/cancelled.
- A later manual request remains possible for an authorized contractor user.

## Rating page and private-feedback form

### Review routing

- Review routing is disabled by default for every contractor.
- **While routing is off**, the feedback page shows every customer the same two clear choices: **Leave a Google review** (opens the contractor's Google review destination) and **Tell us privately** (opens the private-feedback form). Neither choice is hidden, delayed, or dependent on a rating.
- To enable it, the contractor must complete the review-link setup and acknowledge a hard UCRM warning explaining the responsibility and consequences of the chosen routing, including that Google's review policy, the UK CMA, and the US FTC treat asking only satisfied customers for public reviews as prohibited or potentially unlawful.
- The ready-made route is **4–5 stars → Google** and **1–3 stars → private feedback**.
- Contractors can adjust their own routing setup after starting from this default.
- Selecting 4 or 5 stars immediately opens the contractor's Google review destination. UCRM does not show an intermediate thank-you screen.
- Selecting 1, 2, or 3 stars opens the private-feedback form.

### Private-feedback form

- UCRM begins with a useful default form that kindly asks the customer to explain what happened and whether they would like contact from the contractor.
- The contractor can fully edit the wording, add questions, remove questions, and reorder questions. It is not a fixed survey.
- The completed job, client, request, and (when routing is on) the chosen rating are already known to UCRM; the customer should not need to re-enter them.
- After submission, UCRM shows a brief branded thank-you confirmation and creates the private recovery item.

## Reviews workspace and activity

UCRM has one simple **Reviews** area, a top-level item in the main side menu (following HighLevel's top-level Reputation menu; owner decision 2026-09-25), with two tabs:

1. **Requests** — each request's client, completed job, channel, scheduled/sent time, delivery state, feedback-page open, Google-destination click, and final stop reason.
2. **Private feedback** — recovery items that need attention or are already resolved.

The Requests tab uses clear status language: **Scheduled**, **Queued**, **Sent**, **Delivered**, **Failed**, **Feedback page opened**, **Continued to Google**, **Private feedback submitted**, or **Cancelled**.

- The contractor receives a light in-app activity notification when a customer opens the UCRM feedback page.
- The same request activity appears in the client history and completed-job history.
- Before one-click Google connection exists, UCRM shows only what it knows: it may show that the customer continued to Google, but never claims that a Google review was posted.
- Once Google connection is available, connected public reviews may appear in this workspace and be matched to requests where the system has enough evidence.

## Private-feedback recovery

- Each submitted private-feedback form creates a **Recovery item** with the client, job, request, rating (when one was given), answers, and a direct contact path.
- The item begins as **New**, then moves through **Contacting customer**, **Resolved**, and **Closed**.
- An owner, administrator, or approved office manager can assign and handle a recovery item.
- Owners/admins receive an immediate private alert when a new item arrives.
- Fieldworkers can send a review request for their own completed jobs, but cannot view the private-feedback workspace or recovery items.

## Google setup and future connection

### Available now: manual Google destination

- The contractor pastes their Google review link into UCRM once.
- UCRM shows a simple setup checklist and does not let Google-review automation activate until that link is present.
- UCRM uses the saved link for requests and gives the contractor a preview/test route before activation.

### Later: connected Google management

When UCRM can obtain Google access and the contractor connects their Google Business Profile, the next phase adds:

- one-click Google profile connection;
- review importing and live review information;
- matching public reviews to UCRM requests where possible;
- Google review management inside UCRM; and
- AI-assisted review-reply tools.

## Team access

| Person | What they can do |
| --- | --- |
| Owner / administrator | Configure review routing and automation, manage the Google link, send manual requests, view all activity, and handle private feedback. |
| Approved office manager | Send manual requests, view activity, and handle private feedback. |
| Fieldworker | Send a review request for their own completed job only. |
| Other team members | No review or private-feedback access unless a later permission grants it. |

## Product principles

- The contractor starts with a ready-made, easy setup and receives advanced control only where it is useful.
- Messages should sound polite, personal, and business-like—not robotic or generic.
- SMS is the default channel; the contractor can choose email instead for automatic and manual requests.
- Every action should be visible in plain language to the contractor: what was sent, what the customer did, and what needs attention.
- The manual Google-link route delivers useful review requests now. Google review syncing, reply management, and AI tools wait for the later connection phase.

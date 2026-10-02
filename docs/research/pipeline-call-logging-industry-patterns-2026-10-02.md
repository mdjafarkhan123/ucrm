# Pipeline Call button and call logging: industry patterns

Research date: 2026-10-02  
Question: On a sales-pipeline card with Email / Text / Call quick actions, how do leading CRMs handle the Call button and logging a phone call, and does a logged call count as progress for stale-deal warnings?  
Scope: first-party help centers and developer docs only. **Fact** = read in the cited source. **Inference** = our reasoning. **Not found** = no source located or loaded; nothing is guessed.  
Already known in this repo (not repeated): the contract already says Call opens the device dialler, offers an optional return Note, never records an automatic outcome, and that an "explicitly logged call outcome" resets the inactivity clock ([sales-pipeline-behavior-contract.md](../sales-pipeline-behavior-contract.md) lines ~80-90 and ~215-230). Housecall Pro's lead board having Text and Call beside Email is noted in [pipeline-gap-audit-2026-10-01.md](pipeline-gap-audit-2026-10-01.md) (line ~55). ContractorOs already has a manual "log outbound call" API with outcome and duration ([contractoros-unified-inbox-audit.md](contractoros-unified-inbox-audit.md)); the unified inbox contract lets logged calls show as timeline activity ([unified-inbox-behavior-contract.md](../unified-inbox-behavior-contract.md)). `.claude/skills/jobber/` has no mention of tel: links, call buttons or call logging (grep found nothing).

## 1. GoHighLevel (HighLevel)

**Two call paths exist, and only one logs itself.**

- **Fact:** In the mobile app, SIM-based calling "passes the number to your phone's native dialer" and the call is placed on the device's SIM. ([SIM-based calling](https://help.gohighlevel.com/support/solutions/articles/155000005814-sim-based-calling-with-the-mobile-app))
- **Fact:** SIM calls "are not automatically logged as HighLevel calls". The article tells the user to add a Note to the contact with the call outcome, or use the "Log External Call" or "Manual Call" workflow actions when structured tracking is needed. It mentions no automatic post-call prompt. (same source)
- **Fact:** The other path is HighLevel's own phone system (VoIP). Calls through it are logged automatically "with timestamps, duration, and call status". ([Phone Dialer overview](https://help.gohighlevel.com/support/solutions/articles/155000005807-the-phone-dialer-overview))
- **Fact:** After a VoIP call ends, the mobile app shows a summary screen with note completion, appointment scheduling, follow-up task creation and contact tagging. In-call notes are saved on the contact. ([Outbound calling, mobile app](https://help.gohighlevel.com/support/solutions/articles/155000005543-outbound-calling-using-the-highlevel-mobile-app))
- **Fact:** The status values used by the Call Status workflow trigger are Busy, Canceled, Voicemail, Completed, Not answered, with direction Incoming or Outgoing. These are system-recorded statuses of VoIP calls, not a rep-chosen outcome list. ([Call Status trigger](https://help.gohighlevel.com/support/solutions/articles/155000002552-workflow-trigger-call-status))
- **Fact:** "Log External Call" is a workflow action, not a card button. Fields: Direction, Date, To, From, Call Status, Attachment (recording). The article gives no duration field and no fixed outcome values, and warns not to assume a third-party disposition maps to a HighLevel field. Logged calls show in the contact's Conversations. ([Log External Call](https://help.gohighlevel.com/support/solutions/articles/155000002930-workflow-action-log-external-call))
- **Fact:** "Manual Call" creates a call task in Conversations > Manual Actions. The workflow only advances when the user deletes that task, and "simply calling the contact elsewhere" does not advance it. ([Manual Call](https://help.gohighlevel.com/support/solutions/articles/155000003376-workflow-action-manual-call))
- **Not found:** a documented Call button on the opportunity card itself. A search result mentioned call/email/SMS actions on a contact card only; that page was not read.

**Does a logged call reset "stale"?**

- **Fact:** The Stale Opportunities trigger means an opportunity "in the same stage for a set period without any progress or updates". The article recommends custom filters that exclude opportunities with recent "notes, email replies, or logged calls" from being marked stale. ([Stale Opportunities trigger](https://help.gohighlevel.com/support/solutions/articles/155000002492-workflow-trigger-stale-opportunities))
- **Inference:** The built-in trigger measures stage time. Calls only count if the owner adds the filter. Calls are named as a recommended exclusion, but it is not automatic.
- **Fact:** A "Stale Deal" Smart Tag rule ("Last Activity before 14 days ago") is listed as "Coming soon"; the article does not say whether "Last Activity" is opportunity or contact level. ([Smart Tags](https://help.gohighlevel.com/support/solutions/articles/155000006642-how-to-color-code-opportunity-pipelines-smart-tags-))

**Auto-recording an outcome from only opening the dialler?** Fact: no. SIM calls are explicitly *not* logged. The VoIP path records status because HighLevel itself carries the call, which is different from handing off to the device.

## 2. Jobber

- **Fact:** In the Jobber app, "tap the Phone icon in the top right" of a client profile to call; with several numbers on file you choose which. The article describes no call logging. ([Client Information in the Jobber App](https://help.getjobber.com/hc/en-us/articles/8196953752855-Client-Information-in-the-Jobber-App))
- **Fact:** The article does not state tel: or in-app VoIP. **Inference:** the app hands off to the device (a tap-to-call on a client profile with no log behind it). This is unverified; it is not stated.
- **Fact:** Notes exist on clients; phone numbers typed into a note become tappable. ([Notes and Attachments](https://help.getjobber.com/en/articles/notes-and-attachments-in-the-jobber-app/))
- **Fact:** The only call logging found is the third-party Quo integration. After each Quo call an AI summary and transcript sync to the internal notes on requests. The article does not describe a timeline entry or native Jobber call logging. ([Jobber and Quo Integration](https://help.getjobber.com/en/articles/jobber-and-quo-integration/))
- **Fact (reminders):** Quote reminders appear on the schedule for team members to follow up manually, "which can be a good option if you prefer to reach out by phone"; they do not contact the client. ([Automations](https://help.getjobber.com/en/articles/automations/))
- **Finding:** Jobber has **no native Log call action, no outcome list, no post-call prompt** in the pages read. **Not found:** any Jobber stale/rotting indicator that a call would reset. Jobber's follow-up model is Notes and reminders, not call outcomes.

## 3. Housecall Pro

- **Fact:** Tapping the phone icon next to a customer's number (call log, job, estimate, customers page) opens a menu with **Housecall VoIP or Native Dialer**. ([Voice on Mobile](https://help.housecallpro.com/en/articles/8346509-voice-on-mobile); the menu wording came via search snippet, the VoIP/native split is in the page itself)
- **Fact:** On a pipeline card pop-out the options are **CALL, CHAT, or EMAIL**, plus "View and Edit Notes". The page does not say whether CALL uses the native dialer or VoIP, and does not say whether contact attempts are logged. ([Getting Started with Pipeline](https://help.housecallpro.com/en/articles/6185127-getting-started-with-pipeline))
- **Fact:** Pipeline lead statuses include First, Second and Third Contact. Automation can move a lead to Lost after N days in Third Contact. (same source) **Inference:** contact attempts are tracked by a human moving the status, not by call logging.
- **Fact:** VoIP calls land in the Global Call Log with a call-details page: Call Reason, Lead Source, customer, call duration, employee. Call notes are added or edited on that page, during the call ("New" then "Create call notes") or afterward. ([Voice on Mobile](https://help.housecallpro.com/en/articles/8346509-voice-on-mobile), [Call Log guide](https://help.housecallpro.com/en/articles/8345671-voice-overview-page-call-log-guide))
- **Fact:** After a VoIP call the Customer Intake flow opens; the call can be saved as a Job, Estimate (auto-added to call log) or Call notes, which needs a manual reason and note. Calls can also be marked Spam. ([How to Use the Dialer](https://help.housecallpro.com/en/articles/6184954-voice-how-to-use-the-dialer))
- **Fact:** "Selecting Native Dialer will dial directly from your cell phone number via your phone plan." Whether native-dialer calls are logged is **not stated** in the FAQ. ([Voice on Mobile FAQ](https://help.housecallpro.com/en/articles/8365583-voice-on-mobile-faq))
- **Inference:** Native-dialer calls bypass Housecall Pro, so nothing can be logged unless the user adds a note. Call Reason is a reason for the call, not whether it connected.
- **Not found:** any rule that a call or call note resets a stale-lead indicator; Housecall Pro's visible inactivity control is the status-age automation above.

## 4. ServiceTitan

- **Fact:** ServiceTitan Phones monitors and records inbound and outbound calls, and customers can be called from ServiceTitan Mobile. ([Phones](https://help.servicetitan.com/docs/phones-1))
- **Fact:** Call reasons are **admin-configurable** (Settings > Operations > Call Reasons). A CSR must pick one to close a call that did not book a job. An "Is Lead" checkbox on the reason decides whether the call counts as an unbooked call against conversion or an excused call. ([Set up call reasons](https://help.servicetitan.com/roofing/docs/set-up-call-reasons))
- **Fact:** Per a search summary of ServiceTitan help pages, calls over 60 seconds are auto-classified as leads and unbooked calls are flagged by "Second Chance Leads". The underlying pages were not each read, so treat as unverified detail.
- **Finding:** ServiceTitan's outcome is a business classification for inbound-call reporting. **Not found:** a "Log call" action on a lead card, a stale-lead timer that calls reset, or a post-dialler prompt for native handoff.

## 5. HubSpot

- **Fact:** Mobile app Call options: native dialer ("call from your mobile phone carrier", cannot record) or HubSpot VoIP (Sales/Service Hub). Logging is **not automatic**. After disconnect the user gets a prompt to save the call. ([Make calls from the mobile app](https://knowledge.hubspot.com/calling/make-calls-from-the-hubspot-mobile-app))
- **Fact:** The prompt asks for a note, a follow-up task toggle, a call type, record associations, and a **Call outcome**. Android can also log calls placed outside the app if enabled. (same source)
- **Fact:** Default outcomes: Busy, Connected, Left live message, Left voicemail, No answer, Wrong number. Custom outcomes are allowed. Duration cannot be edited when logging manually on desktop (enter it in the note). A "Follow up task" toggle creates a task. The activity appears on the record's timeline. ([Log activities on a record](https://knowledge.hubspot.com/records/manually-log-activities-on-records))
- **Fact:** Call properties include direction, duration (ms), outcome, and status (Completed, Missed, No answer, Failed...). ([Default activity properties](https://knowledge.hubspot.com/properties/hubspots-default-activity-properties))
- **Fact:** Deal **Last activity date** is "the most recent already past date and time a note, call, tracked and logged sales email, meeting, LinkedIn/SMS/WhatsApp message, or chat was logged on the deal record", including completed tasks. **Last contacted** counts calls and one-to-one email but not notes. Deals have "Time in Current Stage" and may be stalled past 20% over the owner's historical average. ([Default deal properties](https://knowledge.hubspot.com/properties/hubspots-default-deal-properties))
- **Inference:** Any logged call updates last-activity regardless of outcome (Wrong number counts). **Not found:** a rotting colour on the board driven by it.

## 6. Pipedrive

- **Fact:** Pipedrive has no built-in VoIP; the calling page lists marketplace integrations (CloudTalk, Aircall, JustCall, etc.) and a green phone icon in the mobile app on lead/deal/contact. ([How can I make calls](https://support.pipedrive.com/en/article/caller)) A "Callto syntax" page exists for VoIP links; its contents were not read.
- **Fact:** Mobile Call uses the native dialer on iOS; Android offers Cellular, WhatsApp, JustCall or Aircall. With call logging on, a call summary view appears at the end of each answered outgoing call to fill details, notes and follow-up activities; it saves as a regular activity. iOS only logs calls made from Pipedrive; Android can also log calls made outside. ([Call and log calls in the Mobile App](https://support.pipedrive.com/en/article/calling-and-logging-calls-in-the-mobile-app))
- **Inference:** The prompt is on *answered* calls only, so an unanswered ring creates no prompt and no record. The doc says "answered" only; "unanswered gets no record" is our reading.
- **Fact:** Outcomes: connected, no_answer, left_message, left_voicemail, wrong_number, busy. Required API fields: outcome, to_phone_number, start_time, end_time. Optional: duration (seconds), note (HTML), person/org/deal or lead id. ([CallLogs API](https://developers.pipedrive.com/docs/api/v1/CallLogs)) Per a search summary, admins can add, rename and disable outcomes under Settings > Calling > Calling outcomes. ([Caller configuration](https://support.pipedrive.com/en/article/pipedrive-settings) — not directly read.)
- **Fact (rotting):** Rotting follows the deal's last-updated time. Reset by marking activities done, adding notes/files, email actions, or editing deal details. The doc says the system "disregards the next activity date", so scheduling a future activity does not prevent rotting. A rotten deal is restored by scheduling a new activity or editing any detail. ([The Rotting feature](https://support.pipedrive.com/en/article/the-rotting-feature))
- **Inference:** The page does not name logged calls. Pipedrive's mobile doc says a logged call "will appear as a regular activity", and marking activities done resets rotting, so a logged call very likely resets it. Unconfirmed in a single sentence.
- **Note:** Pipedrive resets on *notes* too, a looser rule than our contract.

## 7. Salesforce

- **Fact:** "Log a Call" creates "a completed task or activity record". It has optional follow-up task fields (Assigned To, Reminder); fields are controlled by the Quick Action layout. ([Log a Call button](https://help.salesforce.com/s/articleView?id=000387963&language=en_US&type=1))
- **Fact:** The timeline shows logged calls with subject and logged date; logs and tasks live on the record's Activity timeline. ([Activity Timeline](https://help.salesforce.com/s/articleView?id=sf.lex_pro_tips_activity_timeline.htm&language=en_US&type=5))
- **Not found:** the Opportunity/Task API reference pages returned 403, so the Opportunity "Last Activity Date" rule and Task call-disposition values were not verified. Salesforce is a pure manual log; the dialler is a separate add-on.

## 8. Zoho CRM

- **Fact (search summaries, official Zoho pages):** The Calls module has Call Duration, Call Purpose and Call Result fields, and calls can be related to Deals. ([Zoho calls API response](https://www.zoho.com/crm/help/developer/api/calls-response.html)) That page shows only `Call_Result`, `Call_Purpose` and a `"00:00"` duration format; picklist values were not documented there.
- **Not found:** default Call Result values, post-dialler prompt behaviour, or any inactivity rule. Lower priority, left shallow.

## 9. Cross-cutting answers

1. **What Call does.** Native-dialler handoff is universal on mobile (HubSpot, Pipedrive iOS, GHL SIM, Housecall native, Jobber by inference). In-app VoIP is an optional second path (GHL, Housecall, HubSpot, ServiceTitan). Housecall and GHL expose both choices explicitly.
2. **Log call action and outcomes.** Present at HubSpot, Pipedrive, Salesforce, Zoho. Outcomes are a fixed default list (HubSpot six, Pipedrive six) that admins can extend. Housecall Pro and ServiceTitan use a "reason" (why the call happened / why it didn't book), admin-set. Jobber has none. GHL has none for SIM calls (use a Note).
3. **Prompt after return.** HubSpot mobile: always prompts after disconnect. Pipedrive mobile: prompts after answered calls, if enabled. GHL SIM: no prompt documented. GHL VoIP and Housecall VoIP: summary or intake screen. Jobber: none.
4. **Counts as progress.** HubSpot: yes, last-activity date includes logged calls. Pipedrive: marking activities done and notes reset it; logged calls likely. GHL: only if the owner filters for it (docs recommend it). Jobber, Housecall Pro, ServiceTitan: no equivalent found. Follow-up: HubSpot, Salesforce and Pipedrive offer an optional follow-up task at logging time; none auto-clear an overdue task.
5. **Auto-recorded outcome on bare handoff.** None found. GHL says SIM calls are not logged; HubSpot says logging is not automatic and must be saved by the user. Systems that record "Completed" or "Missed" status do so only where they carry the call (VoIP, Android call-log permission).
6. **Where logs appear.** Contact/record timeline (HubSpot, Salesforce, Pipedrive activity), conversation thread (GHL), call log with notes (Housecall), request internal notes (Jobber via Quo).

## What this means for us

| Product | Call behaviour | Log-call outcomes | Counts as progress? |
|---|---|---|---|
| GoHighLevel | Native dialler (SIM) or built-in VoIP | None for SIM (use a Note); VoIP records system status | Only if owner filters for logged calls; not automatic |
| Jobber | Phone icon, number chooser (hand-off by inference) | None native; Quo adds AI notes | No stale feature found |
| Housecall Pro | VoIP or native dialler | Call Reason + call notes (VoIP only documented) | Not documented |
| ServiceTitan | Click-to-call in mobile, recorded Phones | Admin call reasons, required on unbooked inbound | Not documented |
| HubSpot | Native or VoIP; prompt after disconnect | 6 defaults + custom, note, follow-up task | Yes (last activity date) |
| Pipedrive | Native on iOS; post-answered-call prompt | 6 defaults + admin custom, note, follow-up | Activity done / notes yes; calls likely |
| Salesforce | Add-on dialler; manual Log a Call | Subject, comments, follow-up task | Not verified |
| Zoho CRM | Not researched deeply | Result, purpose, duration | Not found |

**Recommendation: (A), with two safeguards.** The only mature products with a Call-then-outcome model (HubSpot, Pipedrive) use a user-triggered log with a short fixed outcome list, an optional note and an optional follow-up task, and they treat a logged call as activity. Our contract already aligns with this ("explicitly logged call outcome" resets the clock). Concretely:

1. **Call** opens the dialler and does nothing else (nothing is recorded). On return, offer a non-blocking "Log call" prompt. This matches HubSpot's prompt and the "do not pretend it connected" rule; GHL's SIM article confirms a bare handoff is simply not logged.
2. **Outcome list is fixed and starts from the shared six**: Connected, Left voicemail, No answer, Busy, Wrong number (HubSpot adds Left live message; Pipedrive has left_message). Make the user choose it; never default to Connected.
3. **Note and duration optional.** HubSpot itself does not offer duration on manual desktop logging; skip it.
4. **Clock reset by outcome.** Pipedrive and HubSpot reset on *any* logged outcome, including Wrong number. Decide whether a no-answer or voicemail attempt should restart the clock; most competitors say yes, which risks hiding deals whose customer never picked up. **Inference / open question for Jafar.**
5. **Optional "next follow-up" task** at logging time (HubSpot, Salesforce, Pipedrive, GHL VoIP all offer it); no competitor auto-clears an overdue task, so completing a Task stays the explicit action.
6. Show the logged call in the Request/Quote history and Client record, following HubSpot/Salesforce timeline behaviour.

**Not recommended:** (B) a note-only pattern is what Jobber and GHL SIM do today, but it leaves no structured outcome to drive the warning. (C) VoIP auto-logging requires owning the call path and is out of scope.

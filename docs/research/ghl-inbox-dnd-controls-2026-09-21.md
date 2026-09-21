# HighLevel inbox DND controls — what it shows, and what UCRM lacks

Date: 2026-09-21  
Scope: how HighLevel (GHL) lets staff stop contacting a customer from inside the inbox, compared with what UCRM already enforces. No code changed.

## Evidence

- `Design/Communications Inbox/ghl-2026-09-21-dnd-tab.png` — the DND tab.
- Live GHL, Jk LTD sub-account: Conversations → Team inbox → Test One, right-hand Contact Details.
- Rules behind the switches (STOP handling, permanent vs temporary DND, workflow skips) are already sourced from HighLevel's help centre in `communications-a2-stage2-consent-balance-sending-safety.md` §1 and `ghl-sms-stage5-automation-behavior.md` §5. They were not re-fetched here.

## What GHL shows (live UI, 2026-09-21)

1. **Contact Details has three tabs: `All fields / DND / Actions`.** DND is a small checklist, not a page.
2. **The checklist:** `DND All Channels`, then "OR" per channel: `Email`, `Text Messages`, `Calls & voicemail`, `Inbound Calls and SMS`.
3. **The inbound row has an info tooltip:** inbound calls from the number are blocked directly; inbound SMS is blocked at system level so no charges are incurred.
4. **Every change is written into the conversation itself** as a centred line, for example "DnD enabled by user for SMS, Email and Call 05:30 AM" and "DnD disabled by user for Email 05:32 AM". Each line shows who and when, and enable/disable use different bell icons.
5. **The thread's header menu is a timeline filter** (All / Conversations / Activities, then per type). Activities is where these DND lines are found.
6. **One row per channel for the whole customer.** The checklist is per customer, not per phone number or email address.

Not verified: what the composer shows when a channel is blocked. The Text Messages checkbox did not respond (this test contact has no phone number), and I stopped after three tries.

## What GHL gets wrong for UCRM's purposes

- One checkbox means three different things: the customer legally opted out, staff chose to pause, or a delivery error occurred. Already noted in `communications-a2-stage2-consent-balance-sending-safety.md` (Departures 1 and 2).
- Any staff member with access can untick it, including a customer's STOP.
- "Calls" and "Inbound" rows have no UCRM equivalent: UCRM has no calling, and blocking a customer from texting in is not a contractor need.

## What UCRM already has

- **Legal opt-out:** STOP handling, append-only SMS consent events (`communication_sms_consent_events`; `source` already allows `staff`), delayed-event ordering. Marketing email has the same shape (`client_marketing_consent_events`, `source` allows `staff`) and a staff endpoint at `src/routes/api/clients/[id=uuid]/marketing-consent/+server.ts`.
- **Holds:** `communication_sms_holds` only at platform, organization or provider scope, per its check constraint. **No per-customer hold exists.**
- **Blueprint:** `docs/communications-sms-product-ui-blueprint.md` already promises a composer reason "SMS is on hold for this customer" and, in Settings, a list of "ordinary contractor holds" — nothing produces that customer-level state today.
- **Email:** suppression list for bounces and complaints; essential vs optional email split from `ghl-email-gap-review.md`.

## Gap

The inbox and customer rail have no contractor-facing control for: "this customer asked me on the phone to stop texting", or "pause messages to this customer for now". The backend cannot record either as a per-customer state, and the rail (Part 4) deliberately omitted it.

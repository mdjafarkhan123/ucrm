# Jafar Business Management — first release proposal

**Status:** Proposal for Jafar's review, 2026-10-07. No release scope is approved yet. This describes user-visible scope, not a coding plan.

## What the first release should achieve

Jafar can take one trade business from research to a paid client without losing its history: add and review the Lead, decide whether and how it may be contacted, record permitted personal contact and replies, arrange a call, share the website pricing link, track the Deal, confirm payment through the existing controls, and hand the client into onboarding. The home view shows the next action and owner. Early Leads stay separate from active Deals, as in [Pipedrive's Leads Inbox](https://support.pipedrive.com/en/article/leads-inbox); dated calls and follow-ups stay attached to the record, as in [Pipedrive Activities](https://support.pipedrive.com/en/article/activities). This is a recommended Uplift release path, not a claim that every planned feature is already built.

The first release should also include the organized six-group `/jafar` Settings home, owner and team invitations with the four agreed role areas and sensitive-action controls, default assignment to Jafar, and a small report of real lead, contact, call, and deal events. These are part of the first journey, even while Jafar works alone.

## Three release choices

| Choice | If included in the first release | If moved to the next release | Recommendation |
| --- | --- | --- | --- |
| Sales booking | Prospects use a public link; `/jafar` controls availability, Busy time, reminders, rescheduling, phone/Zoom/Meet, and automatic or custom video links. [HubSpot's scheduling pattern](https://knowledge.hubspot.com/meetings-tool/create-and-edit-scheduling-pages) supports the usefulness of a self-booking step. | Jafar arranges calls himself and adds them to his `/jafar` calendar; the public link follows later. | Include full booking. Jafar has chosen his app as his only calendar and wants prospects to pick a time. |
| Uplift mailboxes | Ordinary inbound and outbound mail works inside `/jafar`, beginning with `info@upliftcontractor.com` and supporting more addresses, permissions, attachments, and a combined inbox. Activation waits for safe migration and recovery checks. | Keep the current external mail route; staff log relevant email activity in Leads or Deals until UCRM mailboxes are ready. | Move full mailboxes to the next release. The current mail route can support the first sales journey, while [current mail readiness](research/jafar-mail-readiness-2026-10-07.md) does not yet prove that existing mail, delivery, and recovery are safe to cut over. |
| Automated first-contact email | The first release waits for a provider to explicitly permit the exact outreach use and for country, source, and recipient checks to be proven. Only then can approved lists become scheduled individual sends. | Release the Lead list, review, manually completed contact tasks, logging, replies to incoming inquiries, and Deal journey first; add automatic first-contact sending after permission is proven. | Do not hold the usable CRM release for an unapproved provider route. Build the manual path first; the approved list remains idle until Jafar starts contact. |

## Outside the proposed first release

Social-channel cold-message automation, scraping business listings into a prospect database, AI outreach writing, advanced scoring, a separate offer-document maker, and elaborate branching are already outside the approved behavior plan's first useful journey. Other connected channels can follow their own official approval and integration checks. No outbound prospect email is enabled merely because UCRM has a working mailbox.

## What Jafar still needs to choose

1. Public self-booking in release one, or Jafar-managed meeting entry first.
2. Full Uplift mailboxes in release one, or logged external mail first.
3. Launch with manual permitted contact while provider-approved first-contact automation follows, or hold the entire release for provider approval.

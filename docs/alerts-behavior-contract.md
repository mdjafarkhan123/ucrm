# Alerts: behavior contract (CRM launch readiness Part 12)

**Status:** Built 2026-10-12 on branch `codex/alerts-part-12`, awaiting merge and a real-Chrome proof. Approved by Jafar 2026-10-12 (corrected after a database-code review; all three decisions below were
approved as recommended). Web app only; phone push belongs to the native Android and
iPhone apps, built later (Jafar, 2026-10-12).

## Problem

A teammate only learns something happened if they have the CRM open and look at the bell, or read an email. They
cannot choose which alerts reach them, a computer shows nothing when the CRM is in the background, and nobody is
told when they are put on a Visit or Assessment.

## What mature products do (evidence)

| Behavior | Source |
| --- | --- |
| Schedule alerts go to the person scheduled; changes you make yourself never alert you. | Jobber, [Push notifications](https://help.getjobber.com/en/articles/push-notifications-from-the-jobber-app/) |
| Schedule alerts fire when the date or time changes, an item is cancelled, or someone is added or removed. Sales alerts (new request, booking, text, quote viewed, quote approved) go to admins only. | Same |
| Each person turns each alert type on or off in their own Preferences. | Same; Mangomint [staff notifications](https://www.mangomint.com/learn/staff-member-notifications); Bushel (push, email and SMS toggles per topic) |
| Appointment alerts go only to the staff member assigned. Tapping an alert opens the record. | Mangomint |
| Ask for browser permission only when the benefit is obvious, after our own "Enable / Not now" prompt, with a visible way to turn it off. | web.dev, [Permissions UX](https://web.dev/articles/push-notifications-permissions-ux) |

Not found: Jobber's per-type email toggles and Boulevard's staff alert settings. Those are our adaptation.

## How alerts work today (verified in the database code, 2026-10-12)

Every alert is one row in `team_notifications` per person. The bell always shows it. The email column below says
whether an email is also sent today. These rules do **not** change in this release.

| Alert (kind) | Who gets it today | Email today |
| --- | --- | --- |
| Website inquiry received, customer replied | The people the owner picked in **Settings → Inquiry alerts** | Yes |
| Quote approved, changes requested | **One** person: the card's owner, otherwise whoever sent the quote, otherwise the account owner | Yes |
| Quote declined | Same single person | **No, bell only** |
| Quote email could not be delivered | The quote's sender path (see `20261002120000_quote_delivery_failure_is_visible.sql`) | **No, bell only** |
| Invoice paid online, payment failed, overpaid, refund failed, disputed | Everyone active with the permissions that record needs | **No, bell only** |
| Quote deposit paid, failed, overpaid, refund failed, disputed | Same | **No, bell only** |
| Private review feedback | Everyone active with `reviews.feedback` | **No, bell only** |
| Task assigned, you were mentioned | The person named. Self-assigned Tasks never alert. Bulk Tasks are one alert. | Yes |

New alert types in this release (they do not exist today):

| Alert | Who gets it |
| --- | --- |
| Put on Visits or an Assessment | The person assigned |
| Taken off Visits or an Assessment | The person removed |
| Your Visit or Assessment was rescheduled or cancelled | The person assigned |
| Your timer has run more than 12 hours | The person whose timer it is |

## What we adopt

1. **My alerts screen** (Profile → Alerts). Rows are alert types, columns are Bell, Email and Browser. Each person
   changes only their own. Changes save immediately. A row appears only if the person can actually receive that
   alert (a crew member without money permission never sees Money rows; this also keeps the screen ready for the
   Medspa edition).
2. **Owner decides who, each person decides how.** The owner's Inquiry alerts list still decides who can receive
   inquiry alerts. A person on that list then picks Bell, Email and Browser for it. Example: the owner picks Sam;
   Sam turns Email off and keeps Browser. A person not on the list never sees or receives the alert.
3. **Settings only choose channels; they never widen who gets an alert.** The recipient rules in the table above
   are unchanged.
4. **Defaults equal today's behavior, so nothing changes until someone acts.**
   - Bell: on for every alert.
   - Email: on exactly where an email is sent today (inquiries, quote approved/changes, Task alerts) and **off**
     where today is bell only (money, deposits, review feedback, quote declined, quote delivery failure). A person
     can switch Email on for those. New alert types default Email on.
   - Browser: the column stays greyed until the person enables browser alerts on a computer; then Schedule and
     Team alerts start on, everything else off.
5. **Visit and Assessment alerts follow Jobber.** An alert is sent only when someone is added, someone is removed,
   the date or time changes, or the item is cancelled. Changing notes or other details never alerts. A change you
   make yourself never alerts you.
6. **Many at once is one alert.** Assigning someone to a series (a weekly job with 52 Visits) sends one alert:
   "You're on 52 Visits for Smith: weekly mowing, starting Tue 14 Oct". This matches how bulk Tasks already work.
7. **Browser alerts.**
   - Turned on from My alerts, never on page load. Our own "Enable alerts on this computer? Enable / Not now" box
     comes first; the browser's question appears only after Enable.
   - Each computer or browser is listed ("Chrome on Windows") and removable. Alerts go to every listed one.
   - If the browser says Blocked, the screen explains how to unblock it.
   - Clicking an alert opens the same record the bell opens.
   - Works in Chrome on Android phones too (see decision 2). On iPhone it only works after the CRM is added to the
     Home Screen; the screen explains that step.
8. **Shared computers and leavers.**
   - Signing out stops alerts on that computer for that person.
   - Removing a teammate from the business removes all their computers.
   - A computer the browser reports as gone is removed automatically.
9. **Never twice.** One alert is one record. Each channel is sent at most once per alert, and once per computer for
   Browser. A retry after a failure never repeats a channel that already succeeded.
10. **Customers are never notified** by this feature.
11. **Wording example:** "You're on Smith: Spring cleanup, Tue 14 Oct, 9:00 am". The email carries the same words
    and a link.

## Not in this release

- Phone push through native apps, quiet hours, owner-forced alerts, daily digest, text-message alerts to staff.
- **Deferred, not dropped:** the Time clock plan promised "a phone reminder to stop a timer" for this part. This
  release gives a browser, bell and email reminder at 12 hours; the true phone reminder waits for the native apps.
- The bell keeps working exactly as today and always shows every alert sent to the person, even when their Email
  and Browser switches are off. The bell column can't be switched off for alerts the person can receive.

## Technical notes (builder, not for approval)

- Browser alerts need a service worker (`src/service-worker.ts`) and a push-sending worker. Neither exists. The
  four `VAPID_*` values in `.env.example` are placeholders; real keys stay server-side.
- New tables: each person's channel switches per alert type; each registered browser (endpoint, keys, label,
  owner, created, last success).
- The existing email worker's claim-and-retry pattern is reused for the Browser channel.

## Done when

- A teammate on a second computer gets a browser alert within one minute of being put on a Visit, with the CRM
  closed, and clicking it opens that Visit.
- Turning a box off stops that channel for that alert type and nothing else.
- Removing a computer, signing out, or being removed from the business stops alerts on it.
- Existing alerts keep today's recipients and today's email behavior until a person changes a switch.
- A 52-Visit assignment sends one alert. Editing a Visit's notes sends none.
- No alert is sent twice in any channel, including after a failure and retry.

## Decisions (Jafar, 2026-10-12: all three approved as recommended)

1. **Payment and review alerts:** bell only by default like today; each person can switch Email on.
2. **Browser alerts on Android phones:** allowed now, with the iPhone Home Screen step explained on the screen.
3. **Customer texts and emails:** a new message in the inbox is an alert type in this release (Jobber's sales
   alerts include a new text), for people who can see Communications; bell and browser on, email off.

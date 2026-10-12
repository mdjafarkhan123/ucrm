# Alerts: behavior contract (CRM launch readiness Part 12)

**Status:** Proposed 2026-10-12 from Jafar's direction "follow industry-based features". Web app only; phone push
belongs to the native Android and iPhone apps, built later (Jafar, 2026-10-12).

## Problem

A teammate only learns something happened if they have the CRM open and look at the bell, or read an email. They
cannot choose which alerts reach them, a computer shows nothing when the CRM is in the background, and nobody is
told when they are put on a Visit or Assessment.

## What mature products do (evidence)

| Behavior | Source |
| --- | --- |
| Schedule alerts go to the person scheduled; changes you make yourself never alert you. | Jobber, [Push notifications](https://help.getjobber.com/en/articles/push-notifications-from-the-jobber-app/) |
| Sales alerts (new request, new booking, text message, quote viewed, quote approved) go to admins only; non-admins get scheduling alerts only. | Same |
| Each person turns each alert type on or off in their own Preferences. | Same; Mangomint [staff notifications](https://www.mangomint.com/learn/staff-member-notifications) (Notifications tab in profile settings); Bushel (push, email and SMS toggles per topic) |
| Appointment alerts go only to the staff member assigned. Tapping an alert opens the record. | Mangomint |
| Ask for browser permission only when the benefit is obvious, after our own "Enable / Not now" prompt, and give a visible way to turn it off. | web.dev, [Permissions UX](https://web.dev/articles/push-notifications-permissions-ux) |

Verified: the items above. Not found: Jobber's per-type email toggles and Boulevard's staff alert settings. These
are our adaptation.

## What we adopt

1. **My alerts screen** (Profile → Alerts). Rows are alert types, columns are Bell, Email and Browser. Each person
   changes only their own. Changes save immediately.
2. **Alert types, grouped:**
   - **Schedule:** put on a Visit or Assessment; removed from one; your Visit or Assessment moved, cancelled or
     changed.
   - **Sales:** new request or website inquiry, customer replied, quote approved, declined or changes requested.
   - **Money:** invoice paid online, payment failed, overpayment, refund failed, dispute.
   - **Team:** Task assigned to you, you were mentioned.
   - **Reviews:** private feedback.
   - **Time clock:** your timer has run more than 12 hours (the existing "forgotten timer" line).
3. **Who gets what stays as it is today.** Money and Sales alerts go to people who can already see those
   records; Schedule, Team and Time clock alerts go to the person named. Settings only turn channels off; they
   never send an alert to someone who could not see it.
4. **Defaults.** Bell and Email on, as today. Browser off until the person turns it on. Schedule alerts also
   default Browser on once a person has enabled browser alerts on that computer.
5. **Browser alerts.**
   - Turned on from My alerts, never on page load. Our own "Enable alerts on this computer? Enable / Not now"
     box comes first; the browser's own question appears only after Enable.
   - A person can have several computers. Each is listed ("Chrome on Windows") and removable.
   - If the browser says Blocked, the screen explains how to unblock in the browser settings.
   - Clicking an alert opens the same record the bell opens.
6. **Never twice.** One alert is one record; each channel is sent at most once for it, and a retry after a failure
   never repeats a channel that already succeeded. Self-made changes never alert the person who made them.
7. **Customers are never notified** by this feature.
8. **Visit and Assessment alert wording:** "You're on Smith — Spring cleanup, Tue 14 Oct, 9:00 am". The email
   carries the same words and a link.

## Not in this release

- Phone push (native apps), quiet hours, owner-forced alerts, daily digest, text-message alerts to staff.
- The bell keeps working exactly as today and always shows every alert that was sent to the person, even when its
  Email and Browser switches are off.

## Done when

- A teammate on a second computer gets a browser alert within one minute of being put on a Visit, with the CRM
  closed, and clicking it opens that Visit.
- Turning a box off stops that channel for that alert type and nothing else.
- Removing a computer stops alerts on it. A blocked browser shows the unblock help.
- Existing bell and email alerts for Tasks, mentions, quotes, payments and reviews follow the new switches.
- No alert is sent twice in any channel, including after a failure and retry.

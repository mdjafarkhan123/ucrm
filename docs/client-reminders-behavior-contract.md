# Quote alerts and client reminders

**Status:** Planning — Jafar's four choices recorded 2026-10-08; whole plan awaits his approval

## Summary

Contractors learn straight away when a customer says yes to a quote, or asks for changes, online. Their
customers get the messages the client "Communication settings" switches promise: a "you're booked"
confirmation, a reminder before each visit or assessment, overdue-invoice reminders with a pay link, and a
thank-you after the job. The customer messages are ready-made automations, off until the owner turns them on,
like Quote follow-up today. Each client's switch can still turn one off for that client, and the switch says
plainly when the business-wide automation is off, so nobody is told a message goes out when it does not.
Email first; texts join after business registration. Follows Jobber (Core quote-approval notifications; Connect
client notifications, visit reminders, invoice and job follow-ups).

## Quote approved or changes requested online

- When a customer approves a quote, or asks for changes, through their quote link, one person gets a bell
  alert and an email: the deal's owner, else whoever sent the quote, else the account owner — the same person
  the "declined" alert reaches today.
- "Changes requested" shows the customer's message in the alert.
- When the customer approves, they also get a thank-you email at once: their quote is approved and the
  business will be in touch about next steps (Jobber does this; Jafar added it 2026-10-08). It answers the
  customer's own action, so it goes out even when follow-up switches are off; "Do not disturb" still stops it.
- Only the customer's own online answer alerts the team. Jobber's published alerts are about the client
  approving; a teammate recording an approval in the app already knows.
- Jobber also shows approvals to every admin in its activity feed and emails one chosen person; Jafar chose
  the deal owner, by bell and email (2026-10-08).
- Answering twice, or a double-click, never produces two alerts.

## Customer messages: shared rules

- Each message is a ready-made automation in Settings → Automations, off for every business until the owner
  turns it on. The owner can edit the wording and timing. Saving never turns one on.
- A message goes out only when: its automation is on, the client's matching switch is on, the client is not
  on "Do not disturb", and the client has a working email address.
- In the client's Communication settings, a switch whose automation is off reads "Not sending — turn it on in
  Automations", with a link for people allowed to manage Automations.
- Every message is checked again at the moment of sending, against what is true then. A cancelled visit, a
  paid invoice or a switch turned off since means it is not sent.
- No customer ever gets the same message twice for the same visit, invoice or job.
- Sent messages appear in the client's history like every other email.

## "You're booked" confirmation

- One confirmation per job or assessment, not one per visit: Jobber calls it a one-time message, while
  reminders cover each upcoming visit.
- Sent automatically when a visit or assessment is scheduled, once its automation is on (Housecall Pro's way;
  Jafar chose it 2026-10-08). The scheduling screen shows a "Notify customer" tick box, ticked by default;
  unticking it skips the email for that booking. The box does not appear while the automation is off.
- When the date or time changes later, the customer gets an updated "Your visit has moved to …" email, with
  the same tick box.
- It follows the client's "Upcoming assessment and visit reminders" switch, the closest existing one.

## Visit and assessment reminders

- One reminder before each scheduled visit or assessment; default 1 day before, at the same time of day as
  the visit (a Thursday 7 am visit is reminded Wednesday 7 am), as Jobber does. The owner can change it, from
  1 hour to 7 days before, and can pick a fixed time of day instead.
- A visit booked after its reminder time has already passed (say, booked tonight for 8 am tomorrow) gets no
  reminder, so the customer is not sent a "reminder" moments after booking. Jobber and Housecall Pro publish
  no rule for this; it is UCRM's own choice.
- A visit with a date but no set time is reminded at 9 am the day before (Housecall Pro's default), so no one
  is messaged at midnight.
- If the visit moves, the reminder follows the new time. If it is cancelled, deleted or completed first,
  nothing is sent.

## Overdue invoice reminders

- Up to two reminders after an invoice's due date, sent shortly after 8 am local time (Jobber's limits and
  send time). Defaults: 1 day after and 7 days after the due date — the first two after-due steps in Jobber's
  own payment-reminder advice. Each is adjustable up to 90 days and carries the invoice's pay link and
  balance.
- Stopped by: the invoice being paid in full, voided or replaced, or the client's switch being turned off.
- A draft or unsent invoice is never chased.

## Job follow-up

- A thank-you email when a job's work is completed, as Jobber sends its job follow-up when a job is closed;
  sent within the business's sending hours. The owner can add a delay.
- It can run beside the Google review request; the owner can edit either so the customer is not asked twice.

## Still unclear

- Nothing.

Every timing is a default the owner can change. Jobber does not publish its starting numbers; the defaults
above follow Jobber's documented behavior and advice and Housecall Pro's published default.

## Not doing

- Text messages — waits for business registration; the automations gain a text step then.
- "On my way" texts — High list, after registration.
- Telling a teammate they were put on a visit — separate High item.
- Push alerts — separate deferred feature.

## Research

- [Jobber feature catalog, 2026-10-08](research/jobber-feature-catalog-2026-10-08.md)
- [Jobber email gap review](research/jobber-email-gap-review.md)
- Jobber reference: `.claude/skills/jobber/jobber-06-automations-clienthub.md`
- Timing defaults, checked 2026-10-08: Jobber
  [Assessment and Visit Reminders](https://help.getjobber.com/hc/en-us/articles/360033608974-Assessment-and-Visit-Reminders),
  [Automations — Invoice Follow-ups](https://help.getjobber.com/hc/en-us/articles/360021573434--Invoice-Follow-ups),
  [Job Follow-ups](https://help.getjobber.com/hc/en-us/articles/115009739988-Job-Follow-ups),
  [overdue payment reminder advice](https://www.getjobber.com/academy/overdue-payment-reminder-templates/);
  Jobber [Booking Confirmation](https://help.getjobber.com/hc/en-us/articles/360060143753-Booking-Confirmation),
  [Quote Approvals](https://help.getjobber.com/hc/en-us/articles/115012715008-Quote-Approvals);
  Housecall Pro [customer notifications](https://help.housecallpro.com/en/articles/357613-customer-notifications-overview),
  [SMS job reminders](https://help.housecallpro.com/en/articles/8688152-setting-up-sms-job-reminders)
  and [invoice reminders](https://help.housecallpro.com/en/articles/4249157-how-do-i-set-up-invoice-reminders).

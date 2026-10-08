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
- A quote marked approved by a teammate inside the app sends no alert; that person already knows.
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

- Sent when a visit or assessment first gets a date and time. Example: a Tuesday 9 am booking gets "You're
  booked for Tuesday at 9 am" within a minute.
- A recurring job sends one confirmation listing the first visit, not one per visit.

## Visit and assessment reminders

- One reminder before each scheduled visit or assessment; default 1 day before, adjustable from 1 hour to 7
  days.
- A visit booked inside that window (say, tomorrow morning when the reminder is a day ahead) gets no reminder;
  the confirmation covers it.
- A visit with a date but no set time is reminded at the start of the business's sending hours the day
  before.
- If the visit moves, the reminder follows the new time. If it is cancelled, deleted or completed first,
  nothing is sent.

## Overdue invoice reminders

- Up to two reminders after an invoice's due date; default 3 and 10 days after, each adjustable up to 90
  days. Each carries the invoice's pay link and balance.
- Stopped by: the invoice being paid in full, voided or replaced, or the client's switch being turned off.
- A draft or unsent invoice is never chased.

## Job follow-up

- A thank-you email after a job's work is completed; default 1 day later, adjustable.
- It can run beside the Google review request; the owner can edit either so the customer is not asked twice.

## Still unclear

- Nothing. The defaults above (1 day before, 3 and 10 days after due, 1 day after the job) are proposals for
  Jafar's approval.

## Not doing

- Text messages — waits for business registration; the automations gain a text step then.
- A "your visit has moved" message on reschedule — the reminder follows the new time; a notice the staff
  member chooses to send is later work (Jobber asks the staff member each time).
- "On my way" texts — High list, after registration.
- Telling a teammate they were put on a visit — separate High item.
- Push alerts — separate deferred feature.

## Research

- [Jobber feature catalog, 2026-10-08](research/jobber-feature-catalog-2026-10-08.md)
- [Jobber email gap review](research/jobber-email-gap-review.md)
- Jobber reference: `.claude/skills/jobber/jobber-06-automations-clienthub.md`

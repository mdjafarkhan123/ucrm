# Guide contractors to set up a sending email when it is missing

- **Priority:** P3
- **Campaign origin:** invoices Part 6b-1 (Jafar approved 2026-09-06).
- **Reason:** When a business has no verified automated sending identity, Send/Resend on invoices (and quotes)
  refuses with errcode 55000. As of 6b-1 the message is now honest and actionable
  (`src/lib/server/communications/email-send-errors.ts`: "No sending email is set up for your business yet.
  Add and verify one in Settings before sending by email."), but there is still no guided flow that takes the
  contractor from that error to actually connecting and verifying a sending domain/sender. Jafar explicitly
  scoped that setup flow OUT of the 6b-1 task.
- **Reactivation trigger:** we build the "connect your email / verify sending domain" onboarding, or Jafar
  asks to make the send-failure state walk the user through setup rather than only explaining it.
- **Already known:** senders live in `communication_email_senders` + `communication_email_domains`
  (a sender needs `lifecycle_state='enabled'`, `allows_automated`, `is_organization_default`, and a domain
  that is `purpose='sending'`, verified, provider_verified/authenticated, ownership+dkim passing). The error
  message points at "Settings"; confirm the real destination when building the flow.

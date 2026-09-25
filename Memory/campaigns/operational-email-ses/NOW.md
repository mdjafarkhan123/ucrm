# Operational Email on SES: Current Checkpoint

## Goal

Contractor operational email (setup, sending, events, replies) runs on Amazon SES instead of Brevo.

## State

Parts 1, 2a, 2b, 3 all done and committed (`7de601a` in worktree `../Ucrm-email-ses`, branch
`operational-email-ses`). Part 3's migration `20260925130000_operational_email_ses_sending.sql` is live on the
shared remote database. Live-verified on Raad LTD: a real SES-backed sender created through the Settings UI,
assigned to a staff member, a real reply sent and confirmed Delivered from a live SES event.

Part 4 (customer replies on SES) is next. Per ROADMAP.md it needs Jafar's approval before any AWS resource is
created -- present the concrete receipt-rule-set / S3 / SNS / SQS+DLQ topology for approval first, do not start
building.

## Exact next action

Read `ROADMAP.md`'s Part 4 row and "Known constraints", then present the Part 4 AWS topology to Jafar for
approval before writing any code or creating any AWS resource.

## Blockers

Jafar's approval, not yet given, before creating AWS resources for Part 4.

## Pointers

`docs/contractor-email-contract.md`; ROADMAP.md Part 4 row and "Known constraints" (includes a non-obvious
sender-assignment rule found live-testing Part 3).
Resume: `continue operational email ses`.

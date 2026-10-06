# Uplift mail readiness and provider permission (7 October 2026)

Scope: read-only checks for the chosen UCRM-managed Uplift mailbox direction. No mail, account setting, or DNS record was changed.

## What is live now

- Public MX records for `upliftcontractor.com` point to `mx1.hostinger.com` and `mx2.hostinger.com`; nameservers point to Cloudflare. This shows the current delivery route, not whether a Hostinger mailbox is active or contains mail. Those must be checked before any cutover.
- In the configured `us-east-1` SES account, production sending is enabled, but `upliftcontractor.com` is not an SES email identity. The active inbound rule set is `ucrm-ses-inbound-rules`, with the contractor reply rule `ucrm-inbound-all`; it does not establish a working Uplift root-domain mailbox.
- UCRM currently uses Brevo for platform messages and SES for contractor operational and marketing email. The contractor activation verifies a sending subdomain and a reply subdomain while preserving the contractor's root mailbox (`docs/contractor-email-contract.md`). Its per-organization conversations and permissions cannot serve `/jafar` unchanged.

## Provider facts and the choice

Amazon SES is the better transport for Jafar's chosen multiple UCRM-managed addresses: [SES receiving](https://docs.aws.amazon.com/ses/latest/dg/receiving-email.html) accepts mail through an [MX endpoint](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-mx-record.html), and the existing contractor SES transport offers reusable pieces. SES is **not** a ready mailbox or IMAP service. UCRM must provide durable original-mail retention, address routing, search, attachments, spam review, backup/restore, failed-processing recovery, and permission-aware inboxes. Preserve existing mail and prove inbound and outbound delivery before replacing Hostinger MX. [SES S3 receipt action](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-action-s3.html) and [SQS failed-message recovery](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-dead-letter-queues.html) support the technical feasibility, not the existence of those Uplift features today.

[Brevo's free plan](https://help.brevo.com/hc/en-us/articles/208580669-FAQs-What-are-the-limits-of-the-Free-plan) currently includes 300 sends a day, but it does not host the full mailboxes Jafar requested. [Brevo Conversations](https://help.brevo.com/hc/en-us/articles/10668659564818-Connect-and-set-up-your-team-mailbox-in-Conversations) requires an existing mailbox from another provider; connecting more than one mailbox requires Sales Essentials or Sales Advanced. [Transactional sending](https://help.brevo.com/hc/en-us/articles/115000188150-Troubleshooting-Issues-with-Brevo-SMTP) may require Brevo support activation on an account. Neither the free quota nor technical sender verification is prospecting approval.

## Prospect email is a separate gate

[SES production access](https://docs.aws.amazon.com/ses/latest/dg/request-production-access.html) requires acknowledgement that recipients explicitly requested mail. The account's current production status therefore cannot be treated as approval for a new cold-prospect workflow. [Brevo's anti-spam policy](https://help.brevo.com/hc/en-us/articles/209405205-What-is-the-anti-spam-policy-of-Brevo) requires expected, authorized messages, and its [contact-list guidance](https://help.brevo.com/hc/en-us/articles/213405965-Build-a-legitimate-contacts-database-for-optimal-deliverability-and-compliance) rejects email addresses copied from public websites. Pressing Start manually or choosing fewer than 300 people does not change these conditions. Seek the provider's written position on the exact proposed use before enabling that route; also check each recipient's country and source. Until then, approved leads stay idle or become a human contact task where the method is permitted. Replies to people who contacted Uplift are a distinct, expected-mail use; they still require a verified Uplift sender and a working mailbox.

## Product consequence

Use SES for the planned `/jafar` mailbox service after its domain and recovery readiness are proven. Keep Brevo for existing platform messages. Show mailbox readiness separately from recipient/channel eligibility and any provider decision on prospecting. Neither provider is currently a verified automatic first-contact route for Uplift's researched leads.

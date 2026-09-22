# Amazon SES contractor email and reply architecture

Research date: 2026-09-19  
Scope: AWS-backed delivery and reply handling after the provider decision: SES serves contractor-to-customer operational and future contractor marketing email; Brevo remains only for UCRM/Jafar platform mail.

## Recommendation

Use **Amazon SES in `us-east-1` with the established SES receipt-rule receiver**, not Mail Manager, for the first contractor-reply release. Keep the existing UCRM Postgres outbox as the source of truth for sends and the existing Conversations rules as the source of truth for which aliases may create a message.

The receiving path should be:

```text
Customer reply
  -> opaque-address@reply.contractor-domain
  -> SES receipt rule (us-east-1)
  -> private S3 raw-MIME object + SES receipt notification
  -> SNS standard topic -> SQS standard queue -> UCRM inbound-email worker
  -> validate/deduplicate/scan/import attachment -> tenant Conversation
```

This is the smallest AWS-native durable hand-off. Receipt rules can store the original email in S3 and notify SNS; the receipt notification contains the S3 bucket/object key and SES's message ID. SNS then isolates receipt from worker availability, and SQS lets the UCRM worker retry safely. SES supports receiving in US East (N. Virginia) through `inbound-smtp.us-east-1.amazonaws.com`; the SES identity, receipt rules, SNS topic, queue, Lambda (if used), and KMS resources should all stay in that region for the simple deployment. [SES regions and receiving](https://docs.aws.amazon.com/ses/latest/dg/regions.html), [SES receipt notifications](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-notifications-contents.html), [SES endpoints](https://docs.aws.amazon.com/general/latest/gr/ses.html)

Do **not** put full email MIME content directly on SNS as the normal route. SES caps that SNS action at 150 KB and larger mail bounces. The S3 receipt action supports mail up to 40 MB, leaving the worker to apply UCRM's own safer product limits, attachment scan/quarantine policy, and private tenant-scoped storage. [SNS receipt action](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-action-sns.html), [S3 receipt action](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-action-s3.html)

## Why receipt rules, not Mail Manager, now

Both are available in `us-east-1`. Mail Manager adds ingress endpoints, traffic policies, richer rule conditions/actions, optional SMTP relay, archives, and security add-ons; it can also write MIME to S3, publish to SNS, and invoke Lambda. It is a sensible later choice if UCRM needs enterprise gateway controls, searchable regulatory archives, third-party filtering, or multiple mail streams. [Mail Manager overview](https://docs.aws.amazon.com/ses/latest/dg/eb.html), [Mail Manager rules](https://docs.aws.amazon.com/ses/latest/dg/eb-rules.html), [AWS availability announcement](https://aws.amazon.com/about-aws/whats-new/2025/01/ses-mail-manager-available-new-regions/)

Those capabilities do not solve a present CRM requirement better than receipt rules. UCRM's launch scope is narrowly **replies to UCRM-originated mail**, not a hosted contractor mailbox, relay, or broad cold-inbound lead intake. A receipt rule on each verified reply subdomain plus the application alias check supplies the required envelope-recipient routing without introducing Mail Manager resources and commercial archival/security decisions. Re-evaluate Mail Manager only if those later requirements are approved; do not run both receivers for the same reply MX domain.

Classic SES allows many rule sets but only **one active receipt rule set per account and Region**. Therefore all UCRM reply-domain rules in the production account must live in one deliberately owned, versioned `us-east-1` rule set; no contractor or unrelated system may independently activate another one. [SES receipt rules](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-concepts.html)

## Domain and DNS shape

For every contractor, preserve the approved separation:

| Purpose | Suggested subdomain | Required AWS/DNS change |
| --- | --- | --- |
| Visible operational sender | `mail.contractor.example` | Verify an SES domain identity in `us-east-1`; publish its SES-issued DKIM/verification records. |
| Opaque reply receiver | `reply.contractor.example` | Verify it as an SES identity and publish only this subdomain's MX to `inbound-smtp.us-east-1.amazonaws.com` (priority 10); route all received addresses through the reply rule. |
| Envelope bounce/complaint return path | `bounce.mail.contractor.example` | Optional SES custom MAIL FROM MX/TXT records, isolated from both sending and receiving subdomains. |

SES requires proof of domain ownership before receiving and a receiving MX record in addition to identity verification. Identities and their verification are regional, so the same domain must be set up in `us-east-1` where the sending and receiving workloads run. [Receiving setup](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-setting-up.html), [identity/DKIM verification](https://docs.aws.amazon.com/ses/latest/dg/creating-identities.html), [regional SES behavior](https://docs.aws.amazon.com/ses/latest/dg/regions.html)

Never change the contractor's root-domain MX or existing mailbox records. Add only the approved `mail`, `reply`, and (if chosen) `bounce.mail` records after proving the target subdomain is unused. This protects their existing business mailbox while allowing the Reply-To on each UCRM message to be a random, unguessable address such as `r_<token>@reply.contractor.example`.

If custom MAIL FROM is enabled, SES says it must be a subdomain of the verified identity and should not be a subdomain used to send **or receive** email. Its required MX/TXT records receive provider bounce/complaint feedback; that is different from customer replies. [Custom MAIL FROM](https://docs.aws.amazon.com/ses/latest/dg/mail-from.html)

## Worker behaviour and safety controls

1. **Receipt rule:** match the reply subdomain, store the raw MIME in a private S3 bucket, then publish its receipt notification to a standard SNS topic. Give SES only the S3/SNS/KMS permissions required for that action. The real recipient must come from SES's envelope `recipients` field, not untrusted `To`/`Cc` MIME headers. SES documents that headers can differ from actual recipients, including BCC. [Receipt concepts](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-concepts.html), [SES receiving permissions](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-permissions.html)
2. **Queue boundary:** subscribe one standard SQS queue to the topic and configure a queue dead-letter queue/redrive policy plus alarms. A supervised UCRM worker may long-poll that queue on the VPS; Lambda is optional, not required. SNS retries managed SQS delivery, and SNS/SQS dead-letter queues retain failed deliveries for investigation. [SNS dead-letter queues](https://docs.aws.amazon.com/sns/latest/dg/sns-dead-letter-queues.html), [SNS delivery retries](https://docs.aws.amazon.com/sns/latest/dg/sns-message-delivery-retries.html)
3. **Idempotent processing:** make the inbound SES message ID/S3 object key a unique database key before creating a Conversation message, and delete the SQS item only after the database/import transaction succeeds. Standard SQS is at-least-once, so duplicate deliveries are expected; choose a visibility timeout matching actual processing and send repeated failures to the worker DLQ for review. [SQS at-least-once delivery](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/standard-queues-at-least-once-delivery.html), [SQS visibility timeout](https://docs.aws.amazon.com/AWSSimpleQueueService/latest/SQSDeveloperGuide/sqs-visibility-timeout.html)
4. **Validate before exposure:** resolve the opaque alias first; only then accept a known active/guarded alias, associate the organization, parse the MIME, save permitted attachments into UCRM private storage, and create the inbound message. Unknown, expired, suspicious, auto-response, DSN, and loop-pattern mail goes to the approved guarded review/quarantine path, never directly into a customer conversation or automation.
5. **Retention and access:** retain the raw S3 object only for the shortest recovery/forensics window needed, restrict worker IAM to its own prefix, do not expose S3 URLs to the browser, and record the event/object reference separately from the user-visible attachment. The UCRM attachment scanner and authorization layer remain mandatory; SES's receipt scan verdicts are useful inputs, not product authorization.

## Sending events are not customer replies

Use an SES configuration set on every contractor send and publish sending events (at least send, delivery, bounce, complaint, reject, rendering failure, and delivery delay) to a separate topic/queue consumer. SES event publishing includes those event types and associates the event with the originating `mail` record. [SES event data](https://docs.aws.amazon.com/ses/latest/dg/event-publishing-retrieving-sns-contents.html)

That event consumer updates UCRM's delivery projection and its hard-bounce/complaint suppressions. It must never create a Conversations message. Conversely, the inbound receipt consumer must not treat mail receipt as delivery, bounce, or complaint evidence. Keep the two queues, schemas, permissions, DLQs, and idempotency keys separate.

## Implementation gate

Before moving any contractor traffic: verify SES production sending access in `us-east-1`; rehearse DNS changes on a domain with a live external mailbox; send a message with an opaque Reply-To; prove reply-to-Conversation correlation, a duplicate delivery, an oversized attachment, an expired alias, a suspicious/auto-response message, and worker/SQS recovery. Record measured results only—this architecture is not a user-capacity claim.

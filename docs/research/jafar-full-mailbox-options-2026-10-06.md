# Uplift mailboxes inside `/jafar`: options and decision (6 October 2026)

Jafar originally considered one Hostinger mailbox. He then chose to have multiple `upliftcontractor.com` addresses created and used inside `/jafar`, each with its own inbox plus a permission-aware Unified Inbox, without a Hostinger email plan. This document records the options and why the chosen direction needs more work. It does not authorize a purchase, DNS change, account creation, or email send.

## The distinction that matters

UCRM's contractor feature creates **verified sending addresses** on a contractor's domain and receives replies to messages the CRM sent. Its approved contract expressly excludes a general mailbox and unrelated inbound lead mail (`docs/contractor-email-contract.md`, “Conversations and replies”). The contractor Unified Inbox already has a conversation view, composer, attachments, delivery states, assignment, search/filter patterns, and a working SES inbound path. Those are reusable foundations. Its data and server permissions are tied to contractor organizations and customers, and its inbound path does not supply a normal `info@` inbox accepting unrelated mail. The `/jafar` Brevo sender is a fixed transactional identity, with no general mailbox (`src/lib/server/email/brevo.ts`).

An email address must have a receiving service behind the domain's **MX record**. [Amazon SES explains](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-mx-record.html) that SES receiving endpoints are not IMAP/POP mailboxes. They can pass raw mail to the app, but UCRM then owns the mailbox experience and operations. The domain can remain registered at Hostinger even if the mailbox is hosted elsewhere; domain registration and email hosting are separate services.

## Options

| Option | What Jafar sees | Behind the scenes | Fit for Jafar's chosen direction |
| --- | --- | --- | --- |
| **A. Managed mailbox, UCRM interface** | Create/use `info@` and read, search, compose, and reply in `/jafar`. Team permissions and sales records stay in UCRM. Hostinger webmail is only a fallback. | Buy Hostinger Email mailboxes; connect UCRM through its Mail API and incoming webhook. Hostinger stores mail and handles mailbox delivery, spam protection, and recovery. | Simpler for one address, but requires a mailbox plan and more purchased mailboxes as addresses grow. Jafar declined this direction. |
| **B. UCRM-managed mailbox over SES** | Create multiple Uplift addresses in `/jafar`, use each inbox, and see permitted conversations together. No Hostinger mailbox subscription. | Route root-domain mail through SES; receive to S3/queue; UCRM owns durable mailbox storage, recipient routing, search, spam review, attachments, backup/recovery, outbound mail, and bounce/complaint handling. | **Chosen product direction.** Reuse existing SES and Inbox foundations, then build and operate the general mailbox pieces. SES is an email transport, not a ready mailbox. |
| **C. Mail server on UCRM's VPS** | The same in-app inbox. | UCRM operates SMTP/IMAP server software, spam and malware filtering, queues, mail reputation, backups, DNS, security patches, and 24-hour monitoring. | Poor fit for the requested simplicity. It does not remove anti-spam law or recipient-provider filtering. |

### Evidence for the managed-mailbox alternative

[Hostinger's Mail API](https://www.hostinger.com/mail-api) advertises a real inbox with send, read, search, reply, threads, attachments, and webhooks. Its [official SDK guide](https://docs.hostinger.com/api-reference/email-sdks) documents inbox access, sending, replies/forwards, paging, and webhook use. Its [mailbox API reference](https://docs.hostinger.com/api-reference/endpoints/mail/mailboxes) includes a create-mailbox operation; the separate Mail API handles the contents of an existing mailbox. Thus UCRM could offer an in-app “Create `info@`” setup after a Hostinger email plan exists, with credentials kept on the server, and an in-app working inbox. The exact API behavior and access must be tested with Jafar's real plan before promising a one-click setup. A fallback webmail view matters if the UCRM app is unavailable.

The provider's [published plans](https://www.hostinger.com/mail-api) say API and webhooks are included. They also show promotional 48-month prices and higher renewal prices; the checkout terms must be reviewed at purchase. No plan or charge has been selected here.

### What can be reused for the chosen direction

The contractor [Unified Inbox behavior contract](../unified-inbox-behavior-contract.md) and implemented Conversations page already define and show email threads, a composer, attachments, unread and assignment behavior, delivery states, and a mixed-channel view. Existing SES inbound code parses and checks received messages and has a queue-backed route into contractor conversations. Reuse shared components and message-processing pieces after checking their assumptions. The current conversation API and context are based on contractor `organization_id` and `client_id`; copying them unchanged would give Uplift mail the wrong records and permissions. Uplift needs its own address registry, ordinary incoming-mail storage and routing, per-address team access, lead/deal links, and platform-authorized endpoints. A mail sent to two Uplift addresses should appear in both relevant address inboxes but once in Unified Inbox, following the duplicate-handling pattern described by [Front](https://help.front.com/en/articles/2026).

[Amazon SES receiving](https://docs.aws.amazon.com/ses/latest/dg/receiving-email.html) can accept mail and pass it to the app, but its [MX endpoint](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-mx-record.html) is not an IMAP/POP mailbox. Domain-wide receiving needs an explicit registry and rejection of unknown addresses, rather than a silent catch-all. The implementation design still has to verify the domain's current DNS and mail, SES account/region readiness, safe cutover, backup and recovery, and separation from contractor and platform transactional email. Multiple addresses do not imply unlimited capacity or free operation.

### Limits shared by all options

The mailbox choice does not make cold outreach automatically permitted. [Hostinger's policy](https://www.hostinger.com/support/1583510-is-mass-mailing-supported-at-hostinger/) allows legal, solicited mail and disallows unsolicited mail to people who did not opt in. [Amazon SES](https://docs.aws.amazon.com/ses/latest/dg/faqs-enforcement.html) monitors unsolicited sending and may pause it. Running one's own VPS does not remove national rules or Gmail's sender filtering. The 29-person reviewed sequence remains a **product workflow**; each real email-send channel needs a supported sender and recipient eligibility before automation is enabled. `info@` can still receive inbound sales inquiries and reply to people who contacted Uplift.

Do not choose [Amazon WorkMail](https://aws.amazon.com/workmail/) as a new long-term mailbox: AWS currently says it will discontinue support on 31 March 2027.

## Recorded decision and next checks

Jafar approved option B: UCRM-managed Uplift mailboxes in `/jafar`, reusing the contractor Inbox and SES work where suitable. Preserve the existing contractor and platform security boundaries. Before implementation, verify the exact receiving and sending setup, recovery and operating requirements, and a provider-approved route for eligible prospecting. Do not buy Hostinger email, change DNS, or promise that creating an address makes cold automation permissible. The domain can remain registered at Hostinger.

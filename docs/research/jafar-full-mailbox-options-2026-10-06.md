# `info@upliftcontractor.com` inside `/jafar`: mailbox options (6 October 2026)

Jafar plans to buy one Hostinger mailbox, has not said it is active, and would prefer to create and use `info@upliftcontractor.com` entirely inside UCRM if that can be done simply. This document compares the operating model. It does not authorize a purchase, DNS change, account creation, or email send.

## The distinction that matters

UCRM's contractor feature creates **verified sending addresses** on a contractor's domain and receives replies to messages the CRM sent. Its approved contract expressly excludes a general mailbox and unrelated inbound lead mail (`docs/contractor-email-contract.md`, “Conversations and replies”). The current SES inbound worker already parses, scans, and routes reply mail, so some parts are reusable. It does not supply a normal `info@` inbox that accepts any sender, stores all mail, handles folders, search, spam, attachments, and full compose/reply. The `/jafar` Brevo sender is also a fixed transactional identity, with no general mailbox (`src/lib/server/email/brevo.ts`).

An email address must have a receiving service behind the domain's **MX record**. [Amazon SES explains](https://docs.aws.amazon.com/ses/latest/dg/receiving-email-mx-record.html) that SES receiving endpoints are not IMAP/POP mailboxes. They can pass raw mail to the app, but UCRM then owns the mailbox experience and operations. The domain can remain registered at Hostinger even if the mailbox is hosted elsewhere; domain registration and email hosting are separate services.

## Options

| Option | What Jafar sees | Behind the scenes | Fit for one address |
| --- | --- | --- | --- |
| **A. Managed mailbox, UCRM interface** | Create/use `info@` and read, search, compose, and reply in `/jafar`. Team permissions and sales records stay in UCRM. Hostinger webmail is only a fallback. | Buy one Hostinger Email mailbox; connect UCRM through its Mail API and incoming webhook. Hostinger stores mail and handles mailbox delivery, spam protection, and recovery. | **Recommended first.** One app in daily use, much less infrastructure to build. The mailbox subscription remains. |
| **B. UCRM-managed mailbox over SES** | The same in-app inbox, with no Hostinger mailbox subscription. | Point root-domain MX to SES; receive to S3/queue; UCRM owns durable mailbox storage, all inbound routing, search, folders, spam review, attachments, backup/recovery, outbound mail, and bounce/complaint handling. | Technically possible and some existing SES reply code helps, but a substantially larger, ongoing email product. SES is an email transport, not a ready mailbox. |
| **C. Mail server on UCRM's VPS** | The same in-app inbox. | UCRM operates SMTP/IMAP server software, spam and malware filtering, queues, mail reputation, backups, DNS, security patches, and 24-hour monitoring. | Poor fit for one address and the requested simplicity. It does not remove anti-spam law or recipient-provider filtering. |

### Evidence for option A

[Hostinger's Mail API](https://www.hostinger.com/mail-api) advertises a real inbox with send, read, search, reply, threads, attachments, and webhooks. Its [official SDK guide](https://docs.hostinger.com/api-reference/email-sdks) documents inbox access, sending, replies/forwards, paging, and webhook use. Its [mailbox API reference](https://docs.hostinger.com/api-reference/endpoints/mail/mailboxes) includes a create-mailbox operation; the separate Mail API handles the contents of an existing mailbox. Thus UCRM could offer an in-app “Create `info@`” setup after a Hostinger email plan exists, with credentials kept on the server, and an in-app working inbox. The exact API behavior and access must be tested with Jafar's real plan before promising a one-click setup. A fallback webmail view matters if the UCRM app is unavailable.

The provider's [published plans](https://www.hostinger.com/mail-api) say API and webhooks are included. They also show promotional 48-month prices and higher renewal prices; the checkout terms must be reviewed at purchase. No plan or charge has been selected here.

### Limits shared by all options

The mailbox choice does not make cold outreach automatically permitted. [Hostinger's policy](https://www.hostinger.com/support/1583510-is-mass-mailing-supported-at-hostinger/) allows legal, solicited mail and disallows unsolicited mail to people who did not opt in. [Amazon SES](https://docs.aws.amazon.com/ses/latest/dg/faqs-enforcement.html) monitors unsolicited sending and may pause it. Running one's own VPS does not remove national rules or Gmail's sender filtering. The 29-person reviewed sequence remains a **product workflow**; each real email-send channel needs a supported sender and recipient eligibility before automation is enabled. `info@` can still receive inbound sales inquiries and reply to people who contacted Uplift.

Do not choose [Amazon WorkMail](https://aws.amazon.com/workmail/) as a new long-term mailbox: AWS currently says it will discontinue support on 31 March 2027.

## Recommendation to put to Jafar

Keep Hostinger as the quiet mailbox provider for the first `info@` address and make `/jafar` the everyday interface. This meets the practical goal of not switching between tools. It avoids turning UCRM into a mail-hosting company for one account. Do not buy or cancel a plan solely on this research; first confirm Jafar accepts a background mailbox subscription and then test the API with the selected plan. Continue separate work to find a provider-approved method for permitted outbound prospecting.

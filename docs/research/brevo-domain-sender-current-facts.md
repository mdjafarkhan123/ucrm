# Current Brevo domain and sender facts

Research date: 2026-08-24

## Question

What does Brevo currently document for sender-domain lifecycle, DNS authentication status, sender verification, and the separate receiving domain needed for inbound email?

## Sender-domain API

All endpoints use Brevo API v3 and require the secret API key in the `api-key` request header.

| Operation | Request | Documented input and success result | Documented errors |
| --- | --- | --- | --- |
| Create | `POST /v3/senders/domains` | JSON body `{ "name": "mycompany.com" }`. A `200` response includes `id`, `domain_name`, a message, and `dns_records`; current examples also include `domain_provider`. Each DNS record contains `type`, `host_name`, `value`, and Boolean `status`. | `400` for a missing or invalid domain value. |
| List | `GET /v3/senders/domains` | No documented request parameters. A `200` response has `domains`, `count`, `current_page`, and `total_pages`. Current domain entries include `id`, `domain_name`, `authenticated`, `verified`, `provider`, `creator`, and nullable `ip`. | `400` bad request. |
| Get configuration | `GET /v3/senders/domains/{domainName}` | A `200` response includes `domain`, Boolean `verified`, Boolean `authenticated`, and `dns_records`. | `400` bad request; `404` domain not found. |
| Authenticate/recheck | `PUT /v3/senders/domains/{domainName}/authenticate` | No body is documented. It checks the published DNS configuration; a `200` response includes `domain_name` and a success message. | `400` for invalid/missing input or a DKIM/Brevo-code mismatch; `404` domain not found. |
| Delete | `DELETE /v3/senders/domains/{domainName}` | A `200` response is an empty object/null success response, depending on the Brevo page. | `400` bad request; `404` domain not found. |

Sources: [domain creation and management](https://developers.brevo.com/docs/domain-creation-and-management), [create-domain response change](https://developers.brevo.com/changelog/2024/4/9), [list domains reference](https://developers.brevo.com/reference/get-domains), [get configuration reference](https://developers.brevo.com/reference/get-domain-configuration), [authenticate reference](https://developers.brevo.com/reference/authenticate-domain), [delete reference](https://developers.brevo.com/reference/delete-domain), [API authentication](https://developers.brevo.com/docs/authentication-schemes).

### Status meanings

- `verified` means Brevo has verified control of the domain; `authenticated` means the domain authentication setup is complete. Brevo's get-configuration reference explicitly defines each as a Boolean (`true` or `false`).
- A DNS record's Boolean `status` is the validation state of that individual expected record. Creation examples begin with `false`; configuration examples show independently passing and failing records.
- The documented records are Brevo code (ownership), DKIM (message signature), and DMARC (recipient policy). DKIM can be one TXT record or two CNAME records depending on the account. Brevo says DNS propagation can take up to 48 hours, so a pending/failed check is not necessarily terminal.
- SPF and MX are **not required for ordinary Brevo domain authentication**; Brevo says it supplies them when setting up a dedicated IP. Therefore the sender-domain API should not invent an SPF status from the domain's `dns_records`. SPF does appear separately as `spfError` on the sender-create response.
- Brevo says to keep its DNS records unchanged while using Brevo. Modifying or removing them can cause delivery problems or spam placement.

Sources: [get configuration reference](https://developers.brevo.com/reference/get-domain-configuration), [authenticate a domain](https://help.brevo.com/hc/en-us/articles/12163873383186-Authenticate-your-domain-with-Brevo-Brevo-code-DKIM-DMARC), [domain setup guidance](https://help.brevo.com/hc/en-us/articles/35852083084178-Domain-setup-for-better-email-deliverability).

## Sender identities

`POST /v3/senders` creates a sender from required `email` and `name` fields. Dedicated-IP accounts additionally associate IP objects. A `201` response includes the numeric sender `id` and may include `dkimError` and `spfError`; on these error fields, `true` means misconfigured and `false` means well configured. Brevo documents a verification email to the address and says an unverified sender cannot send transactional email.

When the sender's domain is authenticated, Brevo says individual senders on that domain are automatically verified and do not require the six-digit mailbox verification step. The From address still needs to use the authenticated domain. Brevo's current guidance recommends exact sender-domain alignment; authenticating only a root domain while sending from its subdomain can fail DKIM and cause Brevo to replace the sender domain with `brevosend.com`, while an unrelated authenticated domain breaks DMARC alignment.

Sources: [create sender API](https://developers.brevo.com/reference/create-sender), [create a sender](https://help.brevo.com/hc/en-us/articles/208836149-Create-a-new-sender-From-name-and-From-email), [SMTP sender troubleshooting](https://help.brevo.com/hc/en-us/articles/115000188150-Troubleshooting-Issues-with-Brevo-SMTP), [domain setup guidance](https://help.brevo.com/hc/en-us/articles/35852083084178-Domain-setup-for-better-email-deliverability).

## Sending and receiving domains are separate

Brevo's inbound parser requires a receiving domain or subdomain that **differs from the domain used for sending**. Brevo recommends a shape such as `reply.yourdomain.com`. The receiving domain must be verified with Brevo, then delegated to `inbound1.sendinblue.com` and `inbound2.sendinblue.com` using MX records. The inbound webhook is created through `POST /v3/webhooks` with `type: "inbound"`, `events: ["inboundEmailProcessed"]`, and the receiving `domain`; Brevo then parses mail to any address at that domain and POSTs structured JSON to the webhook URL.

This is distinct from the sender-domain endpoints above. A UCRM contract should model outbound sender authentication and inbound MX/webhook readiness separately rather than assume one Brevo domain object proves both.

Source: [Brevo inbound parse webhooks](https://developers.brevo.com/docs/inbound-parse-webhooks).

## Failures and operational implications

- Domain authentication explicitly exposes `400` for invalid/missing parameters or DKIM/Brevo-code mismatch and `404` for an unknown domain. A client can treat these as check failure/not found, but Brevo does not publish a richer machine-readable failure taxonomy on this endpoint.
- Authentication failures can lead mailbox providers to reject, defer, or spam-folder messages. Brevo lists Gmail examples such as permanent `550 5.7.26`, `5.7.27`, `5.7.30`, `5.7.40` and temporary `421` equivalents. These are delivery results, not domain-management webhook events.
- Brevo documents inbound webhook security through IP allowlisting and optional URL/header authentication, but its domain docs do not describe a domain-authentication-status webhook. UCRM should therefore recheck domain state through the get/authenticate endpoints rather than assume Brevo pushes DNS readiness changes.
- Brevo's current webhook retry page documents an unusual policy: after an unresponsive endpoint it pauses delivery for 10 minutes and retries four times (after 10 minutes, 1 hour, 2 hours, and 8 hours), but `4xx` responses other than `429` and **all `5xx` responses** stop retries and discard the webhook/event; `429` remains retryable. A receiver should authenticate and persist valid events idempotently, then return `2xx` promptly. This first-party behavior is important enough to test in the connected account rather than substituting generic webhook retry assumptions.

Sources: [domain authentication API guide](https://developers.brevo.com/docs/domain-authentication-and-verification), [Gmail deliverability troubleshooting](https://help.brevo.com/hc/en-us/articles/36039161138706-Troubleshooting-Deliverability-issues-with-Gmail), [secure webhook calls](https://developers.brevo.com/docs/secured-webhooks), [webhook retry mechanism](https://developers.brevo.com/docs/retry-mechanism).

## Unsupported or uncertain contract assumptions

Brevo's public material reviewed here does **not** establish the following, so Communications Part 2 should not encode them as provider guarantees without account-level testing or Brevo confirmation:

- whether deleting a sender-domain object automatically disables, deletes, or changes existing sender identities on that domain;
- whether deleting or replacing an outbound domain alters inbound webhook configuration (the documented systems are separate, but cascading behavior is not specified);
- whether the same domain can be removed and immediately recreated with the same identifiers or DNS values;
- whether deletion revokes authentication instantly at send time, or how already queued/scheduled messages behave;
- whether every account receives DMARC in the API payload or whether DMARC must be passing for `authenticated: true`. Brevo's current help flow describes Brevo code, DKIM, and DMARC, while older API examples omit DMARC and do not define the exact Boolean formula;
- whether `verified` and `authenticated` can change independently in every currently available setup flow, beyond the examples Brevo publishes;
- pagination request controls for `GET /v3/senders/domains`. The response contains pagination metadata, but the current reference documents no query parameters;
- a webhook event for sender-domain authentication changes or DNS-record failures.

For safe replacement/removal, UCRM should first stop new sends, inspect dependent senders, scheduled/queued mail, and inbound routing, then remove the Brevo domain only after an explicit impact preview. That sequence is a UCRM safety recommendation, not a documented Brevo cascade contract.

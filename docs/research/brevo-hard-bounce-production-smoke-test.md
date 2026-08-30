# Brevo hard-bounce production smoke test

Research date: 2026-08-29

## Question

What is the safest supported way to prove Brevo hard-bounce webhook receipt and UCRM suppression behavior, and is a nonexistent controlled subdomain a reliable hard-bounce target?

## Verdict

Do **not** approve `bounce-test@nomx.upliftcontractor.com` on the claim that “no MX” guarantees an immediate Brevo hard bounce. Use a layered gate:

1. Verify the live webhook's URL, event subscriptions, batching, and authentication without changing it. Brevo's webhook API returns those fields, and `hardBounce` must be among the transactional events. [Get all webhooks](https://developers.brevo.com/reference/get-webhooks)
2. In Brevo's webhook UI, use the supported **Send test request** action for the Transactional email → Hard Bounced event. This proves Brevo can call the configured public endpoint without sending mail or adding a real bounce. It proves ingress/authentication, but a generated fixture does not prove correlation to a real UCRM message or provider-side blocklisting. [Brevo outbound-webhook test requests](https://help.brevo.com/hc/en-us/articles/27824932835474-Create-outbound-webhooks-to-send-real-time-data-from-Brevo-to-an-external-app)
3. Prove callback parsing, idempotency, processor execution, local suppression, and resend cancellation with a correlated synthetic fixture in staging. Do not claim this from step 2 unless the received test payload actually carries identifiers that resolve to the prepared UCRM record.
4. If approval specifically requires the **real production send → SMTP rejection → Brevo classification → webhook → local suppression** chain, run exactly one tagged send to a controlled permanent-rejection target, after the precautions below. A deterministic target is an MX host under the team's control that rejects the unique test recipient during `RCPT TO` with `550 5.1.1`; RFC 5321 defines `550` as mailbox unavailable, and RFC 3463 defines `5.1.1` as a nonexistent destination mailbox usable only for permanent failures. [RFC 5321](https://www.rfc-editor.org/rfc/rfc5321.html), [RFC 3463](https://www.rfc-editor.org/rfc/rfc3463.html)

Brevo documents a supported webhook-event generator and a send-request sandbox, but the current official documentation and API index reviewed do **not** document a special bounce-simulator recipient address. Brevo's sandbox only validates the API request: it sends no email, creates no logs, and therefore cannot produce a real delivery/bounce lifecycle. [Brevo sandbox mode](https://developers.brevo.com/docs/using-sandbox-mode), [Brevo official documentation index](https://developers.brevo.com/llms.txt), [transactional webhook reference](https://developers.brevo.com/docs/transactional-webhooks)

## Why the proposed no-MX address is not reliable

- Under SMTP, an empty MX result is treated as an implicit MX pointing to the same host, so the sender falls back to its A/AAAA addresses. Merely omitting MX is not a “no mail” declaration. An NXDOMAIN must be reported as an error, but that still does not dictate Brevo's event mapping. [RFC 5321, address resolution](https://www.rfc-editor.org/rfc/rfc5321.html#section-5.1)
- Brevo explicitly lists “the domain name doesn't exist” among common **soft-bounce** causes and may defer/retry such mail for up to 36 hours. It therefore cannot support the promise of a prompt `hard_bounce` callback from a nonexistent subdomain. [Brevo bounce handling](https://help.brevo.com/hc/en-us/articles/209435165-What-are-soft-bounces-and-hard-bounces-in-email)
- If the only goal is guaranteed non-delivery, `.invalid` is permanently reserved and resolvers should return NXDOMAIN; use it instead of a randomly invented `.com`. It still does not guarantee Brevo will classify the result as `hard_bounce` rather than `invalid_email`, `deferred`, or `soft_bounce`. [RFC 6761, `.invalid`](https://www.rfc-editor.org/rfc/rfc6761.html#section-6.4), [Brevo transactional event types](https://developers.brevo.com/docs/transactional-webhooks)
- If the team wants a domain that explicitly accepts no mail, the standard DNS mechanism is a **Null MX** (`MX 0 .`), not an absent MX. RFC 7505 says this should fail immediately with permanent `556 5.1.10`. Brevo does not document how it maps Null MX to its event names, so this is a good permanent-nondelivery probe but not a guaranteed `hard_bounce` fixture. [RFC 7505](https://www.rfc-editor.org/rfc/rfc7505.html)

## Precautions for the one real production bounce

Before sending, record the following evidence:

- The webhook ID is the intended account webhook; its exact URL is the live UCRM endpoint; `hardBounce`, `invalid`, `blocked`, and `deferred` are subscribed as required; and its bearer/custom-header authentication is present. Redact secret values in the evidence. [Brevo webhook configuration API](https://developers.brevo.com/reference/get-webhooks)
- The Brevo account has no suspension or deliverability warning, and the current send/bounce denominator is known. Do not call one bounce “negligible” without that denominator. Brevo says hard-bounce rates above 2% can suspend campaigns and that poor transactional results can suspend the transactional platform, although it publishes no separate transactional numeric threshold. [Brevo suspension rules](https://help.brevo.com/hc/en-us/articles/360017299259-Why-have-my-account-or-email-campaigns-been-suspended)
- The target is owned and deterministic: a dedicated test subdomain/MX or an existing controlled recipient system proven to reject that exact local part with permanent `550 5.1.1`; no catch-all, forwarding, or real mailbox can receive it. If an isolated Brevo sub-account is already available, prefer it for destructive deliverability tests; Brevo describes sub-accounts as independent with separate reports, contacts, and API keys. [Brevo sub-account isolation](https://help.brevo.com/hc/en-us/articles/9003097317138-Classic-Admin-account-What-is-sub-accounts-management)
- Use one unique recipient and one unique UCRM/Brevo tag; record the enqueued message ID, Brevo message ID, callback event, processor result, and timestamps. Brevo recommends tags for querying received events. [Brevo webhook correlation with tags](https://developers.brevo.com/docs/how-to-use-webhooks)

Afterward, verify both UCRM's local suppression and Brevo's provider blocklist, then enqueue the second UCRM send. Prove that UCRM's worker cancels it **before any second Brevo API request**. Brevo automatically blocklists hard-bounced addresses and exposes the reason through its blocked-contact API, so a second Brevo `blocked` event would prove provider protection but would **not** prove UCRM's suppression recheck. Retain the dedicated synthetic address as suppressed rather than repeatedly unblocking and rebouncing it. [Brevo hard-bounce blocklisting](https://help.brevo.com/hc/en-us/articles/209435165-What-are-soft-bounces-and-hard-bounces-in-email), [blocked transactional contacts API](https://developers.brevo.com/reference/get-transac-blocked-contacts)

Stop rather than improvise if the generated Brevo test request cannot correlate to a UCRM message, the controlled receiver does not produce the expected permanent SMTP reply, the account is low-volume or already unhealthy, or Brevo maps the controlled failure to another event. In that case, ask Brevo Support to confirm a sanctioned simulator address or the expected event mapping before creating a production bounce.

## Recommended response to the operator

> Don't use option 1 as written. “No MX” does not guarantee an immediate hard bounce, and Brevo documents nonexistent domains as a possible soft-bounce case. First use Brevo's built-in **Send test request** for the Hard Bounced webhook event and prove callback receipt. Then prove correlated suppression in staging. If a real production bounce is still required, come back with a controlled MX target that returns `550 5.1.1`, the current account bounce denominator/health, and the exact one-send evidence plan. Do not describe the reputation impact as negligible until that evidence is shown.

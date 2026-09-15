# Bulk marketing email delivery safety

**Researched:** 2026-09-15  
**Scope:** Safe delivery behavior for UCRM's first contractor email-campaign release. This is product guidance, not a measured capacity claim.

## Recommendation in one sentence

The contractor should press **Send once**, UCRM should freeze the approved recipient snapshot and enqueue one marketing campaign, and delivery should then happen progressively at a steady, provider-controlled rate—not as thousands of direct SMTP/API sends in one second.

## Why

- Gmail explicitly tells bulk senders to increase volume slowly, send at a consistent rate, avoid bursts and sudden spikes, begin with engaged recipients, and reduce volume if bounces or deferrals rise. It also recommends separating promotional and transactional message types by sending identity, and, where multiple IPs are used, by IP. [Gmail email sender guidelines](https://support.google.com/mail/answer/81126)
- Brevo's campaign API treats “Send now” as scheduling the campaign for the current time; Brevo then moves it through queued/scheduled, running, and sent states. Provider acceptance is therefore not the same as immediate delivery to every inbox. [Brevo: send a campaign now](https://developers.brevo.com/reference/send-email-campaign-now), [Brevo campaign statuses](https://help.brevo.com/hc/en-us/articles/209429605-Why-is-my-campaign-set-as-Scheduled-before-Running-Sent)
- Brevo offers campaign batching with intervals specifically to pace delivery and reduce traffic spikes. Its API rate ceilings describe request capacity, not a safe deliverability target; Brevo itself says requests should be distributed evenly and `429` responses must be handled. [Brevo campaign scheduling and batches](https://help.brevo.com/hc/en-us/articles/4413566705298-Create-and-send-an-email-campaign), [Brevo API rate limits](https://developers.brevo.com/docs/api-limits)

## Product behavior for the first release

### Submit once; deliver progressively

Use Brevo's **marketing campaign** primitive rather than looping over recipients through the transactional email endpoint. At final confirmation:

1. Re-check sender readiness, consent, suppression status, credits/plan readiness, content, links, and the exact recipient count.
2. Freeze an immutable recipient snapshot and campaign version for audit/history.
3. Submit or schedule the campaign once and show `Queued`, then provider-backed progress such as `Sending`, `Sent`, `Suspended`, or `Failed`.
4. Let Brevo apply mailbox-provider pacing. For a new or materially changed sending domain, a large list, or an unusual volume increase, use deliberate batches/steady throttling rather than a burst. Start with the most recent, engaged, clearly consented recipients and expand only while results stay healthy.

Do not label a campaign “delivered” when Brevo merely accepted it. Delivered, bounced, complained, and unsubscribed are later per-recipient events.

### Domain and traffic isolation

- Require an authenticated sending domain before launch: SPF and DKIM at minimum; configure DMARC and alignment as the safe default. Gmail requires SPF or DKIM for all senders and SPF, DKIM, DMARC, alignment, and one-click unsubscribe for senders over its 5,000-messages-per-day threshold. [Gmail email sender guidelines](https://support.google.com/mail/answer/81126)
- Use a stable marketing sender identity (for example, `offers@...` or `news@...`) distinct from receipts, password resets, booking notices, and other operational mail. Gmail recommends consistent `From` addresses per message category and separate IPs per message type when multiple IPs are used. [Gmail email sender guidelines](https://support.google.com/mail/answer/81126)
- Marketing must never occupy or delay UCRM's transactional job queue. Give password resets, quotes, invoices, booking confirmations, and similar operational mail a separate queue with higher priority. Where the provider/account supports it, use separate marketing and transactional streams/senders and eventually separate IP pools. Brevo distinguishes campaigns from its transactional platform; on shared infrastructure, marketing problems can still affect queued transactional mail, so application-level isolation remains necessary. [Brevo: marketing vs transactional email](https://help.brevo.com/hc/en-us/articles/360021196220-What-are-the-differences-between-marketing-transactional-and-automation-emails), [Brevo: why emails enter a queue](https://help.brevo.com/hc/en-us/articles/360021917460-Why-are-emails-added-to-a-queue)

### Warm-up and throttling

- A “Send” click may enqueue immediately; it must not bypass warm-up or pace controls.
- Do not hard-code “all campaigns send over X minutes” as a universal promise. Safe speed depends on prior domain/IP volume, cadence, engagement, recipient mailbox mix, bounces, complaints, deferrals, provider plan, and shared-versus-dedicated IP behavior.
- On a new/inactive domain or a dedicated IP, start low and increase gradually. Gmail says larger volumes should rise more slowly and recommends steady sending without bursts. Brevo's campaign API exposes dedicated-IP warm-up controls and currently recommends a 30% daily increase from an initial quota of 3,000 for that feature; those are provider defaults, not proof that the same numbers fit every UCRM tenant. [Gmail email sender guidelines](https://support.google.com/mail/answer/81126), [Brevo: update campaign/warm-up fields](https://developers.brevo.com/reference/update-email-campaign)
- Shared IPs are the simpler starting point for occasional low-volume contractors because Brevo describes them as already warmed and suitable for hundreds or thousands of emails once or twice monthly. A dedicated IP is not automatically safer; it needs consistent volume and its own warm-up. [Brevo: shared vs dedicated IP](https://help.brevo.com/hc/en-us/articles/209466865-Differences-between-a-shared-IP-and-a-dedicated-IP)
- Automatically slow or stop the remaining campaign when provider deferrals, bounces, or complaint signals breach a deliberately conservative safety rule. Gmail specifically says to reduce volume when bounces or deferrals begin and to monitor SMTP responses and reputation. [Gmail email sender guidelines](https://support.google.com/mail/answer/81126)

### Unsubscribe, complaint, and bounce handling

- Promotional email must contain a visible unsubscribe link and standards-based one-click unsubscribe headers. Gmail requires one-click unsubscribe for marketing/subscribed messages from bulk senders; its FAQ says this must use the `List-Unsubscribe` mechanism rather than only a body link. [Gmail email sender guidelines](https://support.google.com/mail/answer/81126), [Gmail sender FAQ](https://support.google.com/mail/answer/14229414)
- Process marketing webhooks for at least delivered, hard bounce, soft bounce, spam complaint, and unsubscribed. Webhook handling must be idempotent because retries or duplicate delivery are possible. [Brevo marketing webhooks](https://developers.brevo.com/docs/marketing-webhooks), [Brevo webhook events](https://developers.brevo.com/reference/create-webhook)
- Immediately suppress future marketing for unsubscribe, spam complaint, invalid address, and hard bounce. Never delete the suppression record, because deletion can allow accidental re-import. Brevo automatically blocklists hard bounces and recommends retaining blocklisted contacts; it also warns that resubscribing someone who opted out can be illegal. [Brevo bounce handling](https://help.brevo.com/hc/en-us/articles/209435165-What-are-soft-bounces-and-hard-bounces-in-email), [Brevo blocklist guidance](https://help.brevo.com/hc/en-us/articles/5317448358034-Blocklist-unblock-or-resubscribe-contacts)
- Re-check suppression immediately before each recipient is handed to the provider, including later batches. A recipient who opts out after scheduling but before their batch begins must not receive that remaining marketing email.
- Keep marketing and transactional consent/suppression meanings separate. A marketing opt-out must stop promotions but should not normally block essential requested receipts, security notices, or service updates.

### Cancellation boundary

- Before provider submission: Cancel returns the campaign to draft or cancels the scheduled send with no recipients released.
- After provider submission but before/during sending: expose **Stop remaining emails**, call the provider's campaign `cancel`/`suspended` status, and stop any UCRM batches not yet handed off. Brevo exposes campaign status operations including `cancel` and `suspended`. [Brevo campaign status API](https://developers.brevo.com/reference/update-campaign-status)
- After a recipient has been handed to Brevo or accepted by the recipient's mail server, UCRM cannot reliably recall that message. The UI must say how many were already handed off/sent and how many were stopped; it must never imply that cancellation recalls mail already released.

## Safety thresholds and evidence limits

Gmail requires reported spam below 0.3% and recommends keeping it below 0.1%; Brevo says results such as hard bounces over 2%, unsubscribes over 1%, or complaints over 0.2% can lead to suspension. These are provider enforcement/health signals, not targets to approach. UCRM should alert and pause earlier after production baselines are measured. [Gmail sender FAQ](https://support.google.com/mail/answer/14229414), [Brevo suspension guidance](https://help.brevo.com/hc/en-us/articles/360017299259-Why-have-my-account-or-email-campaigns-been-suspended)

Without staged, production-like tests and observed provider behavior, the plan **cannot promise**:

- a fixed number of emails per second or campaigns per hour;
- inbox placement, open rate, or conversion rate;
- an exact completion time after Send;
- support for 40,000 users or any simultaneous-campaign load;
- that cancellation stops messages already accepted downstream;
- that an API's published maximum rate is a deliverability-safe rate.

Before making capacity or delivery-time claims, measure representative tenant sizes, concurrent campaigns, provider latency/rate limiting, webhook lag and duplication, queue isolation under load, cancellation effectiveness, retry behavior, bounce/complaint feedback, and the effect on transactional-email latency.

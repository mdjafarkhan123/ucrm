# Email reputation thresholds for a shared Brevo account

Research date: 2026-08-15

## Question

Which complaint, bounce, and bulk-sender thresholds are official requirements from Brevo, Gmail, and Yahoo, and which earlier UCRM alert or pause points should protect a shared multi-tenant Brevo account?

## Official provider requirements and enforcement

| Provider | Official threshold or rule | Status and consequence |
| --- | --- | --- |
| Brevo | Complaint rate above **0.2%**, hard-bounce rate above **2%**, or unsubscribe rate above **1%** can lead to suspension of the account or email campaign. Brevo evaluates recent campaigns, including campaigns sent in the previous 24 hours and sampled sends to new contacts. | Published Brevo suspension triggers. They are not safe operating targets. A second suspension may not be self-reactivatable. Brevo can also temporarily suspend transactional sending for negative results, but its public article does not publish a separate transactional numeric threshold. [Brevo suspension reasons](https://help.brevo.com/hc/en-us/articles/360017299259-Why-have-my-account-or-email-campaigns-been-suspended), [Brevo deliverability guidance](https://help.brevo.com/hc/en-us/articles/360020418259-Best-practices-for-email-deliverability) |
| Gmail | All senders to personal Gmail accounts must keep the Postmaster Tools spam rate below **0.3%**. Google separately says to keep it below **0.1%** and avoid ever reaching **0.3%**. The rate is calculated daily from user reports. | The 0.3% value is an official sender requirement; below 0.1% is Google's recommended operating level. At more than 0.3%, bulk senders are ineligible for delivery mitigation until the rate remains below 0.3% for seven consecutive days. Delivery may also be limited, rejected, or placed in spam when requirements are not met. [Gmail sender guidelines](https://support.google.com/mail/answer/81126?hl=en), [Gmail sender FAQ](https://support.google.com/mail/answer/14229414?hl=en) |
| Gmail | A bulk sender is one sending about **5,000 or more messages to personal Gmail accounts in 24 hours**. Bulk senders need SPF and DKIM, DMARC with at least `p=none`, From-domain alignment, and one-click unsubscribe for marketing/subscribed mail. Google says unsubscribe requests must be honored within **48 hours**. | Official bulk-sender requirements. Once classified as a bulk sender, the sender remains classified that way; spreading messages across subdomains does not avoid classification. Transactional messages are excluded from the one-click-unsubscribe requirement. [Gmail sender guidelines](https://support.google.com/mail/answer/81126?hl=en), [Gmail sender FAQ](https://support.google.com/mail/answer/14229414?hl=en) |
| Yahoo | All senders must keep spam complaints below **0.3%**. Yahoo calculates the rate from mail delivered to the inbox and continuously evaluates mail; mail from a domain above the 0.3% enforcement threshold may be affected or deferred. | Official sender requirement and enforcement threshold. Yahoo does not publish a numeric volume that defines a bulk sender. [Yahoo sender best practices](https://senders.yahooinc.com/best-practices/), [Yahoo sender FAQ](https://senders.yahooinc.com/faqs/) |
| Yahoo | Bulk senders need SPF and DKIM, passing DMARC with at least `p=none`, From-domain alignment, one-click unsubscribe for marketing/subscribed messages, and unsubscribe processing within **2 days**. | Official bulk-sender requirements. Yahoo may send noncompliant mail to spam or reject it. Transactional messages are excluded from its one-click-unsubscribe requirement. [Yahoo sender best practices](https://senders.yahooinc.com/best-practices/), [Yahoo sender FAQ](https://senders.yahooinc.com/faqs/) |

Neither Gmail nor Yahoo publishes a general numeric bounce-rate ceiling in these sender requirements. Both instruct senders to monitor bounces/SMTP responses, remove invalid recipients, slow sending when deferrals or bounces rise, and avoid repeatedly sending to invalid addresses. Therefore, **2% is a Brevo suspension-risk threshold, not a Gmail or Yahoo requirement**. [Gmail sender guidelines](https://support.google.com/mail/answer/81126?hl=en), [Yahoo sender best practices](https://senders.yahooinc.com/best-practices/), [Yahoo SMTP errors](https://senders.yahooinc.com/smtp-error-codes/)

## UCRM product recommendations

The following are proposed UCRM safeguards, not provider-published requirements:

| Signal | Warn | Automatically pause affected organization's optional email | Escalation |
| --- | --- | --- | --- |
| Complaint rate | **0.05%** | **0.10%** | At **0.20%**, keep the organization paused and alert Jafar urgently because Brevo suspension risk has been reached. Never wait for the Gmail/Yahoo 0.30% ceiling. |
| Hard-bounce rate | **1.0%** | **2.0%**, or earlier when a sudden invalid-recipient pattern appears | At 2.0%, keep the organization paused and alert Jafar urgently because Brevo suspension risk has been reached. |
| Unsubscribe rate for marketing | **0.5%** | **1.0%** | At 1.0%, keep marketing paused and alert Jafar because Brevo suspension risk has been reached. This metric must not pause expected transactional email by itself. |

Apply these controls per organization, sending domain, message lane, and rolling observation window, while also watching the entire Brevo account. A proposed implementation should:

- suppress a recipient immediately after a complaint or hard bounce, independent of whether a rate threshold has been reached;
- alert on both the organization's rate and the shared-account aggregate, since Brevo may suspend the shared account or campaign;
- pause marketing and optional automations first; do not automatically release their backlog after recovery;
- preserve a separately rate-limited essential operational lane only while platform-wide Brevo health remains safe;
- require Jafar review before resuming an organization at or beyond a Brevo threshold;
- use minimum evidence rules so one event in a tiny sample does not pretend to be a stable rate, while still treating that recipient-level event immediately. A reasonable starting rule is rate-based automatic pausing after at least **1,000 accepted recipients**, or after **3 complaints** / **20 hard bounces** in the observation window, whichever detects risk first;
- calculate at least a rolling 24-hour view for rapid protection and a rolling 7-day view for persistent degradation. Gmail's own Postmaster complaint measure is daily and Yahoo continuously evaluates mail, so UCRM should retain provider-specific dashboard signals rather than assume its Brevo event rate equals the mailbox provider's denominator.

The exact minimum sample, event-count trigger, and rolling windows above are UCRM product defaults. Jafar should be able to tighten them platform-wide or per organization, but an organization override should not be allowed to weaken the platform safety ceiling without an explicit Platform Owner action and audit history.

## Shared-account implication

Different contractor domains help domain reputation and attribution, but they do not fully isolate a shared Brevo account or shared sending IP. Gmail explicitly notes that an IP quota is shared by all senders using that IP, while Yahoo warns that traffic from other domains on a shared IP can harm delivery. UCRM therefore needs tenant-level attribution and pausing before traffic reaches Brevo, plus a platform emergency pause even when each contractor uses a verified domain. [Gmail sender guidelines](https://support.google.com/mail/answer/81126?hl=en), [Yahoo SMTP errors](https://senders.yahooinc.com/smtp-error-codes/)

## Decision boundary

Official requirements belong to the providers and may change. UCRM should treat the provider values as hard external ceilings, refresh them before implementation, and store its earlier internal warning and pause thresholds as configurable platform policy rather than hard-coded business constants.

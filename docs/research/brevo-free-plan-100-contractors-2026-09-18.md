# Brevo Free plan for 100 contractor organizations

**Researched:** 2026-09-18  
**Source boundary:** Current first-party Brevo Help Center and API documentation only.  
**Question:** Can one Brevo Free account safely and practically provide UCRM marketing email for 100 independent contractor businesses?

## Answer in one sentence

**No.** The Free plan is useful for a small internal proof, but one shared account is neither large enough nor correctly isolated for 100 independent contractor organizations; Brevo's documented multi-organization isolation is an Enterprise, custom-priced feature.

This conclusion contains both hard facts and an architectural inference. Brevo states the limits and account behavior below. The judgment that these behaviors are unsafe for UCRM's tenant model is an inference from those facts.

## Hard limits Brevo documents

### Free plan

- Price: **$0/month**, with no expiry or credit card requirement.
- Sending: **300 email sends per day**, shared by marketing and transactional email. The quota resets daily and unused sends do not roll over.
- Contacts: **up to 100,000 stored contacts**.
- Users: **one account owner**.
- Automation: **up to 2,000 unique contacts** can enter active automations.
- Branding: Free emails always include a **Sent with Brevo** mark.
- Reporting: Free includes basic statistics, not the advanced reporting available on higher plans.
- A campaign may contain more than 300 recipients, but only 300 receive it that day. Brevo says the remainder must be resumed manually, at most once per 24 hours as the next quota becomes available.
- Once the daily quota is exhausted, another campaign cannot be scheduled in advance for the next day.

Sources: [Brevo Free-plan limits](https://help.brevo.com/hc/en-us/articles/208580669-FAQs-What-are-the-limits-of-the-Free-plan), [Brevo plans and pricing](https://help.brevo.com/hc/en-us/articles/208589409-About-Brevo-s-pricing-plans), [resume a suspended campaign](https://help.brevo.com/hc/en-us/articles/4411394977810-Send-to-new-contacts-resume-duplicate-and-archive-email-campaigns), [email credit behavior](https://help.brevo.com/hc/en-us/articles/8292912279954-Add-or-remove-emails-from-your-plan).

The 300-send allowance is an **account-wide daily send allowance**, not 300 per contractor, campaign, sender, list, or API key. Brevo also says quotas apply per active account across the platform, integrations, and API actions. [Brevo account quotas](https://help.brevo.com/hc/en-us/articles/9168632514066-What-are-the-different-quotas-applied-in-Brevo)

### Account, campaign, and list quotas

For Free, Starter, and Standard accounts, Brevo documents:

- **3 accounts maximum owned by the same company**;
- **10,000 stored email campaigns**, including drafts;
- **150 email campaigns scheduled at the same time**;
- **300 contact lists** and **300 contact folders**;
- **200 contact attributes**;
- **40 outbound webhooks** and **20 inbound webhooks** per account.

These object quotas apply to the whole Brevo account, not separately to UCRM contractors. [Brevo account quotas](https://help.brevo.com/hc/en-us/articles/9168632514066-What-are-the-different-quotas-applied-in-Brevo), [Brevo API platform quotas](https://developers.brevo.com/docs/platform-quotas)

### API limits that materially affect an integration

Brevo's general API tier, available on Free, documents:

- contact endpoints: **36,000 requests/hour and 10 requests/second**;
- most other endpoints, which include ordinary campaign-management calls unless separately listed: **100 requests/hour**;
- exceeding a rate limit returns **HTTP 429**; Brevo provides remaining/reset headers and recommends retry/backoff;
- sending a campaign checks the account's send limit and credit balance; insufficient credits produce **HTTP 402**;
- campaign test sends are limited to **50 test emails per day**.

These are API-request ceilings, not additional email credits and not evidence that a given email volume will be delivered safely. Sources: [Brevo API rate limits](https://developers.brevo.com/docs/api-limits), [rate-limit headers](https://developers.brevo.com/docs/limit-headers), [send campaign now](https://developers.brevo.com/reference/send-email-campaign-now), [send a campaign test](https://developers.brevo.com/reference/send-test-email).

## Capacity arithmetic for 100 contractors

The following is arithmetic from the hard **300 sends/day** limit, not a production-capacity promise.

In a 30-day month, one shared Free account has a theoretical maximum of **9,000 sends**. Divided evenly among 100 contractors, that is only **90 recipient-emails per contractor per month** before allowing any headroom for tests, mistakes, retries, transactional email, or uneven demand.

| Assumed use per contractor | Shared monthly sends | Minimum fully-used sending days | Result |
| --- | ---: | ---: | --- |
| 1 campaign × 25 recipients | 2,500 | 9 | Fits arithmetically, but with little room for normal growth |
| 1 campaign × 50 recipients | 5,000 | 17 | Fits only if sending is carefully spread across the month |
| 1 campaign × 90 recipients | 9,000 | 30 | Consumes the entire theoretical 30-day allowance |
| 1 campaign × 100 recipients | 10,000 | 34 | Cannot finish within a 30-day month |
| 2 campaigns × 100 recipients | 20,000 | 67 | More than two months of continuous quota |
| 1 campaign × 250 recipients | 25,000 | 84 | Nearly three months of continuous quota |
| 1 campaign × 500 recipients | 50,000 | 167 | Not operationally plausible on Free |

Another way to read the same limit:

- one campaign per contractor per month: at most **90 recipients each** in a 30-day month;
- two campaigns per contractor per month: at most **45 recipients per campaign**;
- four campaigns per contractor per month: at most **22.5 recipients per campaign**.

All of these figures assume every daily credit is used perfectly. Brevo explicitly says unused Free credits do not roll over, and campaigns larger than the remaining daily quota require manual resume. Real usable capacity would therefore be lower.

## Why lists inside one account do not isolate 100 businesses

### Hard facts

- A contact email address must be unique to one contact record. The same contact can belong to multiple lists, and Brevo deduplicates a recipient appearing in multiple lists. [Brevo contact import format](https://help.brevo.com/hc/en-us/articles/208729849-Create-a-file-to-import-your-contacts), [import contacts](https://help.brevo.com/hc/en-us/articles/115000719584-Import-your-contacts-to-Brevo), [campaign recipient deduplication](https://help.brevo.com/hc/en-us/articles/15152720243730-Exclude-and-filter-recipients-from-your-email-campaigns)
- Marketing email subscription status is stored for the contact/channel. If the contact is blocklisted from email campaigns, Brevo says they will not receive **any** email campaigns from that account. Lists can remove a contact from a topic/list, but they are not separate campaign blocklists. [types of blocklisted contacts](https://help.brevo.com/hc/en-us/articles/209458705-FAQs-What-are-the-different-types-of-blocklisted-contacts), [blocklist and resubscribe behavior](https://help.brevo.com/hc/en-us/articles/5317448358034-Blocklist-unblock-or-resubscribe-contacts), [view blocklisted contacts](https://help.brevo.com/hc/en-us/articles/5311015528594-View-your-blocklisted-contacts-unsubscriptions-complaints-hard-bounces)
- Fine-grained **consent groups** are available only on Professional and Enterprise plans. [Brevo blocklist and consent-group availability](https://help.brevo.com/hc/en-us/articles/5317448358034-Blocklist-unblock-or-resubscribe-contacts)
- Free has one owner/user. It does not provide 100 contractors their own isolated access. [Brevo users and plan limits](https://help.brevo.com/hc/en-us/articles/360001079439-Add-and-manage-users-on-your-Brevo-account)

### UCRM inference

If homeowner `alex@example.com` is a customer of Contractor A and Contractor B, one shared Brevo account represents Alex as one contact with one set of contact attributes and one campaign blocklist state. An unsubscribe from Contractor A's promotion would therefore block campaigns from Contractor B as well. Conversely, treating a list removal as a full unsubscribe would be easy to get wrong. This is not the business-specific consent and suppression isolation an independent multi-tenant CRM needs.

Lists and custom fields could label which contractor supplied a contact, but they do not create an independent contact database, independent API credentials, independent campaign blocklist, or independent user boundary. A mistake, complaint spike, quota exhaustion, or account restriction would also share one operational blast radius. The last sentence is an architectural inference; Brevo does not make a UCRM-specific safety judgment.

## Brevo's documented isolation options

### Enterprise sub-organizations/sub-accounts

Brevo describes sub-account management specifically for agencies, multiple clients, and multiple business entities. It says sub-accounts are completely independent and provide separate contact lists, dashboards, and unique API keys. This is the Brevo-native shape that matches 100 independent contractor organizations.

However:

- sub-organization management is an **Enterprise** feature;
- Enterprise has a **custom price**, available by sales quote rather than a published per-subaccount price;
- the maximum number of sub-organizations and consumables is defined by the negotiated Enterprise plan;
- credits are allocated to individual sub-organizations from the Admin account.

Sources: [Brevo sub-account management](https://help.brevo.com/hc/en-us/articles/9003097317138-Classic-Admin-account-What-is-sub-accounts-management), [create sub-accounts and allocate credits](https://help.brevo.com/hc/en-us/articles/8999563717906-Classic-Admin-account-Create-sub-accounts-and-allocate-monthly-credits-from-your-Admin-account), [Enterprise price/features](https://help.brevo.com/hc/en-us/articles/208589409-About-Brevo-s-pricing-plans), [new Admin billing FAQ](https://help.brevo.com/hc/en-us/articles/22853299659282-FAQs-Billing-and-payment-for-new-Admin-accounts).

There is no official public number in these sources for what 100 sub-organizations would cost. A Brevo sales quote is required.

### Separate contractor-owned accounts through Brevo's Agency Partner model

Brevo also documents an Agency Partner Program in which each client owns or creates their own Brevo account (including a Free account), approves the agency, and the agency can switch between and manage client accounts. Applying to the Agency Partner Program is described as free. [Brevo Agency Partner client accounts](https://help.brevo.com/hc/en-us/articles/360021519719-Invite-your-clients-to-Brevo-as-an-Agency-partner)

This is genuine account separation, but the cited documentation describes human partner access, not an embedded SaaS authorization model for UCRM. It does not establish that UCRM may silently create accounts for contractors, use one master API key across client accounts, or offer an in-app send experience without each contractor's account setup and authorization. Those points require written confirmation from Brevo before treating this as a product architecture.

Creating 100 Free accounts owned by UCRM is not an alternative: Brevo documents a maximum of three accounts owned by the same company on Free, Starter, Standard, and Professional. [Brevo account quotas](https://help.brevo.com/hc/en-us/articles/9168632514066-What-are-the-different-quotas-applied-in-Brevo)

## Recommendation and unresolved questions

Do **not** create the shared production Brevo account yet. First choose and validate the tenant-isolation/commercial model:

1. Ask Brevo for an Enterprise quote for **100 independent sub-organizations**, including monthly sends, shared versus separate reputation controls, API access, webhook scope, and growth pricing.
2. Ask Brevo in writing whether its Agency Partner model supports an embedded CRM integration in which each contractor authorizes their own account, and how API credentials, webhooks, campaign creation, billing, and revocation work.
3. Compare those answers against a provider designed for multi-tenant SaaS sending before locking UCRM to Brevo.
4. Use one Free account only for an internal, non-customer proof of campaign creation, unsubscribe/blocklist event handling, and webhook behavior. Its 300/day limit is enough for that narrow test, not evidence for 100-contractor support.

The commercial choice remains unresolved because Brevo does not publish the Enterprise price for 100 sub-organizations and the Agency Partner article does not document the API/embedded-product permissions UCRM needs.

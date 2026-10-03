# Contractor setup content research

**Date:** 2026-10-03  
**Scope:** The complete prebuilt setup brief for Uplift clients: common CRM configuration plus Premium website,
Google Business Profile, Calls and texting, Review requests, and Marketing campaigns. Sources are first-party
product, provider, regulator, and public-service design guidance.

## Executive finding

The proven pattern is a resumable task list with shared business facts first, then operational defaults, then
only the service-specific stages the client bought. It should not be one giant form or an empty editor. Ask one
fact once, reuse it downstream, route with short filter questions, visibly mark optional items, accept
**I don't know** or **I need help** where honest, and show a complete check-and-approve page before freezing the
brief. This matches the [GOV.UK multiple-task](https://design-system.service.gov.uk/patterns/complete-multiple-tasks/),
[task-list](https://design-system.service.gov.uk/components/task-list/),
[question-page](https://design-system.service.gov.uk/patterns/question-pages/), and
[check-answers](https://design-system.service.gov.uk/patterns/check-answers/) patterns. NHS guidance likewise
recommends [filter questions](https://service-manual.nhs.uk/content/how-to-write-good-questions-for-forms/use-filter-questions-to-route-users)
and checking [why each question is needed](https://service-manual.nhs.uk/content/how-to-write-good-questions-for-forms/make-sure-you-need-each-question).

Three different rules must not be collapsed:

1. **Stage visibility** comes from the purchased package service.
2. **Question visibility** comes from country and earlier answers.
3. **Readiness** comes from whether the missing fact or access task truly blocks the selected work. A response
   can be required while **Need help** is still a valid response and a named follow-up.

## Common contractor setup

Mature contractor systems start with one shared truth before downstream configuration. Jobber sequences company
details, business profile/branding, settings, taxes, team, and payments in its
[basic account setup](https://help.getjobber.com/en/articles/first-steps-basic-account-set-up/); its
[company settings](https://help.getjobber.com/en/articles/company-settings/) feed documents, email footers,
Client Hub, scheduling, and phone forwarding. Housecall Pro similarly orders company profile, employees,
customer import, price book, SMS registration, and document/payment defaults in its
[getting-started checklist](https://help.housecallpro.com/en/articles/11115983-getting-started-with-housecall-pro).
ServiceTitan says common prerequisites should be configured once before downstream workflows in its
[admin checklist](https://help.servicetitan.com/docs/admin-setup-checklist-in-servicetitan-max) and
[cross-feature workflow](https://help.servicetitan.com/docs/servicetitan-max-cross-feature-workflow-reference-guide).

Therefore Uplift should collect:

- public and legal identity, main contact/final approver, private operating address and public-display choice,
  country, language, time zone, currency, public contact route, and customer-facing hours;
- real services, work not offered, customer type, emergency availability, priorities, real service areas and
  exclusions, travel limits, and genuinely staffed locations;
- reusable logo, brand choices, factual differentiators, proof, licences, insurance, warranties, photos,
  testimonials with sources, and publishing permission; and
- plain-scenario CRM defaults: assessment versus direct booking, enquiry recipient/owner, quoting, scheduling,
  deposits, invoice terms, tax treatment, payment instructions, and team responsibilities.

Tax and registration identifiers are conditional facts, not universal curiosity. They appear when invoicing,
telecom registration, an appeal, or another selected path actually needs them. Google recommends
[people-first, first-hand content](https://developers.google.com/search/docs/fundamentals/creating-helpful-content)
and says to focus on useful site structure rather than meta-keyword thinking in its
[SEO starter guide](https://developers.google.com/search/docs/fundamentals/seo-starter-guide); contractors
should supply facts, not finished SEO copy.

Branding is shared content, not only a website concern. Jobber applies one
[business profile](https://help.getjobber.com/en/articles/business-profile/) to request forms, Client Hub,
emails, and documents. Housecall Pro centralises logo, description, messages, and terms in its
[company profile](https://help.housecallpro.com/en/articles/1363783-set-up-your-company-profile). Google asks
for [clear photos that represent reality](https://support.google.com/business/answer/6123536?hl=en). Missing
optional brand assets should not block setup when Uplift can supply an agreed starter alternative.

## CRM behavior and imports are separate

Operational configuration should use everyday scenarios. Jobber distinguishes request-only, assessment
booking, and direct job booking in [Requests and Bookings](https://help.getjobber.com/en/articles/requests-and-bookings-settings/)
and [Request basics](https://help.getjobber.com/en/articles/request-basics/), while its
[invoice payment terms](https://help.getjobber.com/en/articles/set-invoice-payment-terms/) have sensible
defaults and overrides. Contractors should answer what normally happens, not configure an event engine.

Import is optional and has its own preview/approval path. Housecall Pro recommends using the one
[most up-to-date source](https://help.housecallpro.com/en/articles/136068-what-are-the-options-for-importing-my-customers-into-housecall-pro)
to avoid duplicates, then lets users correct suggested mappings before
[importing](https://help.housecallpro.com/en/articles/6797101-how-to-import-export-jobs-and-customers).
Jobber documents useful service/price fields in its
[products and services list](https://help.getjobber.com/en/articles/products-services-list/), while
ServiceTitan treats its [pricebook](https://help.servicetitan.com/docs/en/pricebook) as a foundation and
supports [structured import/export](https://help.servicetitan.com/v1/docs/import-and-export-your-pricebook).
The setup brief can request a source and file, but import requires a separate validation preview and explicit
commit approval.

## Website and domain

Start with **I own a domain / someone else controls it / I need one / not sure**. Existing-domain intake must
identify the registrar, registrant contact, renewal owner, DNS controller, current host, business-email
provider, and other live subdomains/services before any DNS change. Cloudflare documents scoped
[member access](https://developers.cloudflare.com/fundamentals/manage-members/) and
[role management](https://developers.cloudflare.com/fundamentals/manage-members/manage/); it also explains
why [MX, SPF, DKIM, and DMARC records](https://developers.cloudflare.com/dns/manage-dns-records/how-to/email-records/)
must be preserved. Google Search Console likewise supports
[delegated users and owners](https://support.google.com/webmasters/answer/7687615?hl=en). Uplift should prefer
delegated access or supervised changes and never request a password.

The contractor supplies goals, facts, process, proof, restrictions, and examples; Uplift drafts the pages.
WordPress's official guidance separates purposeful
[pages](https://wordpress.com/support/pages/) and confirms a domain may remain registered elsewhere while
[connected](https://wordpress.com/support/domains/connect-existing-domain/). Setup submission is not launch
approval.

## Google Business Profile

Route first by existing/new/someone-else/not-sure/suspended/duplicate state. Reuse business facts, then ask only
Google-specific gaps. Uplift should propose the smallest specific category set for client approval instead of
making the contractor guess SEO categories; this follows Google's
[category guidance](https://support.google.com/business/answer/3038177?hl=en).

Google distinguishes storefront, service-area, and hybrid businesses. A service business that does not serve
customers at its address should hide it; Google accepts up to 20 named service areas and recommends a broadly
two-hour operating boundary rather than a radius field. See Google's
[service-area guidance](https://support.google.com/business/answer/9157481?hl=en) and
[area editing rules](https://support.google.com/business/answer/10514743?hl=en).

The contractor stays primary owner and invites Uplift as manager using Google's
[owner/manager roles](https://support.google.com/business/answer/3403100?hl=en) and
[agency access model](https://support.google.com/business/answer/7663063?hl=en). Verification is an external
task chosen by Google, sometimes requiring live video proof; codes must not be stored or shared. See
[verification methods](https://support.google.com/business/answer/7107242?hl=en-en) and
[video verification](https://support.google.com/business/answer/14271705?hl=en-IM). Existing listings use
[ownership requests](https://support.google.com/business/answer/4566671?hl=en-GB); suspension evidence is
requested only when an [appeal](https://support.google.com/business/answer/4569145?hl=en-6) actually needs it.

## Calls and texting

Route by country and desired number path: new, forwarding, hosted messaging, port, or advice. Housecall Pro's
[voice settings](https://help.housecallpro.com/en/articles/6750234-voice-settings-overview) use open/closed
hours and employee/ring groups; Twilio's [`<Dial>`](https://www.twilio.com/docs/voice/twiml/dial) supports
forwarding, timeout, and no-answer outcomes. Those translate into plain routing questions about who rings,
order, delay, busy/no-answer/after-hours handling, voicemail, alerts, language, and testing.

Porting requires exact carrier identity, authorised user, service address, account number, protected port PIN,
recent bill, and signed authorisation. Twilio explains the matching requirements in its
[porting guide](https://help.twilio.com/articles/223179348-Porting-a-Phone-Number-to-Twilio) and
[Port-In API documentation](https://www.twilio.com/docs/phone-numbers/port-in/port-in-request-api). Passwords
and time-limited OTPs are never ordinary questionnaire answers.

Telecom evidence depends on country, number/sender type, and use case. Twilio's
[regulatory workflow](https://www.twilio.com/docs/phone-numbers/regulatory/getting-started) and
[A2P business-information list](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc/collect-business-info)
support collecting universal identity/authorised-representative facts first, then current provider-required
registration, opt-in wording/evidence, samples, volume, links/numbers, terms/privacy URLs, and STOP/HELP facts.
The contractor supplies what happened and what recipients saw; Uplift maps those facts to applicable rules.

## Reviews and marketing

Reviews work even without Google Profile management by accepting the contractor's official review link or
creating a help prerequisite. Google documents the
[review-link/QR flow](https://support.google.com/business/answer/16816815?hl=en-GB). Jobber's
[review automation](https://help.getjobber.com/en/articles/reviews-marketing-tools/) is useful for trigger,
channel, timing, reminder cap, repeat suppression, and opt-out structure. Uplift must deviate from any
preferred-client or happiness-based targeting: Google's
[Business Profile policy](https://support.google.com/business/answer/7400114?hl=en) and
[merchant restrictions](https://support.google.com/contributionpolicy/answer/16597558?hl=en) prohibit
selective positive solicitation, discouraging negative reviews, pressure, and incentives.

Marketing intake needs goal, audience and exclusions, service/area, offer terms and capacity, sender, reply
owner, channel, schedule, tone, call to action, recipient countries, audience source, exact consent evidence,
and suppression list. Mailchimp's [campaign checklist](https://mailchimp.com/help/create-and-send-regular-email/)
and [campaign planning](https://mailchimp.com/help/about-campaign-manager/) use the same practical fields.
Recipient-location facts matter because email/SMS rules differ across the
[US](https://www.ftc.gov/business-guidance/resources/can-spam-act-compliance-guide-business),
[UK](https://ico.org.uk/for-organisations/direct-marketing-and-privacy-and-electronic-communications/guide-to-pecr/electronic-and-telephone-marketing/),
[Canada](https://crtc.gc.ca/eng/com500/guide.htm),
[Australia](https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/organisations/direct-marketing),
and [EU](https://eur-lex.europa.eu/eli/dir/2002/58/oj). Setup creates a draft only; a later preview and explicit
send/schedule approval remain mandatory.

## Required question capabilities

The complete content needs more than text boxes: single and multiple choice, repeating structured groups,
addresses, hours, money/numbers, files with purpose/rights, restricted evidence, existing-record selectors,
reused read-only values with a **Change source** link, confirmations, access/action tasks, import preview state,
and a versioned approval snapshot. One simple follow-up may reveal inline; a branch containing several
questions should become its own page or task, following GOV.UK
[radio](https://design-system.service.gov.uk/components/radios/) and
[checkbox](https://design-system.service.gov.uk/components/checkboxes/) accessibility guidance.

These are content requirements for the later coding campaign. They should not be flattened into ambiguous
long-text questions merely to fit the current editor.


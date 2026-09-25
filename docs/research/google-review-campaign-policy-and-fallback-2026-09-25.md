# Google review campaign: policy and no-API fallback research

Researched: 2026-09-25. This is factual source research for the review-campaign planning discussion, not an approved feature contract or implementation plan.

## Decision-critical findings

### 1. A star-rating split before Google is not allowed

The proposed journey—send 5-star customers to Google but route 1–4-star customers only to a private form—is **review gating**. Google says merchants must not “discourage or prohibit negative reviews, or selectively solicit positive reviews from customers.” It allows a business to ask for a genuine review only where it does not influence the rating or review content. Incentives for a review, change, or removal are also prohibited. [Google Maps User Generated Content Policy](https://support.google.com/contributionpolicy/answer/7400114?hl=en).

**Planning consequence:** do not offer a contractor setting for star thresholds or sentiment-based Google routing. A private feedback option can be offered to every recipient, but it must not hide, delay, or condition the same recipient’s Google-review opportunity. Rating can help the contractor prioritise service recovery *after* feedback, not decide who may review publicly.

### 1a. UK and US consumer regulators say the same

The UK CMA's fake-reviews guidance (CMA208, paras 4.3 and 4.5) says a trader may infringe the law by cherry-picking positive reviews, including "by encouraging just those who are satisfied to leave reviews." [CMA208 Fake reviews guidance](https://assets.publishing.service.gov.uk/media/67eeb64fe9c76fa33048c790/CMA208_-_Fake_reviews_guidance.pdf). The US FTC's guide for marketers states: "Don't ask for reviews only from customers you think will leave positive ones." [FTC: Soliciting and paying for online reviews](https://www.ftc.gov/business-guidance/resources/soliciting-paying-online-reviews-guide-marketers).

**Owner decision (2026-09-25):** routing stays in the plan as a contractor opt-in behind a hard warning; it is off by default, and the default page offers every customer both a Google review and a private-feedback choice.

### 2. The review-request campaign can launch without Google API approval

Google explicitly lets a Business Profile owner generate a “Get more reviews” link or QR code and share the link in receipts, thank-you emails, or chats. No API connection is involved. [Google: create a review link or QR code](https://support.google.com/business/answer/16816815?hl=en).

**Safe first-release setup:** the contractor opens their own verified Google Business Profile, copies that official review-request link, and pastes it into UCRM. UCRM can then send the contractor’s approved SMS campaign and link every eligible recipient to Google. The product should make clear that clicking the link is known, but posting a review is not confirmed without later Google access.

Without Google API access, UCRM cannot reliably pull the public review list, show real-time review data, match reviews, or publish a reply. The contractor still manages those parts in Google.

### 3. “One-click Google connect,” review pulling, and publishing replies are a later phase

Google’s current prerequisites require a Google Cloud project, an Organization account, an API-access application, and approval. The applicant must manage a verified active Business Profile for 60+ days and have a matching business website; Google indicates an unapproved project has zero API quota. [Google Business Profile API prerequisites](https://developers.google.com/my-business/content/prereqs). Each connected contractor also needs to grant OAuth permission and may revoke it later. [Google OAuth implementation](https://developers.google.com/my-business/content/implement-oauth).

Once that access exists, Google’s review API supports listing/retrieving reviews and creating, changing, or deleting the business’s reply. [Google review-data API guide](https://developers.google.com/my-business/content/review-data). That is the boundary for later review syncing and a human-approved AI reply assistant; it is not a blocker for sending the official copied review link now.

### 4. Ten or more SMS nudges in one month is not a sound default or an open contractor setting

Google does not publish a numeric SMS-reminder limit, but it prohibits unusual review-volume/pattern manipulation and selective positive solicitation. More directly, SMS review requests are non-essential marketing-type messages in Twilio’s US compliance tooling, which applies quiet-hours protection. [Twilio Compliance Toolkit](https://www.twilio.com/docs/messaging/features/compliance-toolkit).

Twilio’s A2P process requires the sender’s campaign to document how recipients opt in, opt out, get help, and what the messages are for; US application-to-person texts over a 10-digit long code require A2P 10DLC registration. [Twilio A2P overview](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc). Its opt-out safeguards recognise STOP-like keywords and block later messages; consent records should preserve opt-in/opt-out status and when/how it was obtained. [Twilio consent and opt-out controls](https://www.twilio.com/docs/messaging/features/compliance-toolkit).

For the intended launch countries, the rule is not just a carrier concern: UK electronic-marketing texts normally need the recipient’s specific consent (with a limited existing-customer exception), identity, a working opt-out, and retained evidence. [ICO PECR electronic-marketing guidance](https://ico.org.uk/for-organisations/direct-marketing-and-privacy-and-electronic-communications/guidance-on-direct-marketing-using-electronic-mail/how-do-we-comply-with-the-pecr-electronic-mail-marketing-rules/). Canada requires consent, identification, and a functioning unsubscribe route for commercial electronic messages. [CRTC CASL FAQ](https://crtc.gc.ca/eng/com500/faq500.htm).

**Planning consequence:** SMS cannot be “send as many nudges as a contractor chooses.” Every campaign needs valid recorded consent for its use, sender identification, clear STOP/unsubscribe handling, recipient-local sending windows, immediate suppression after opt-out, and an auditable record. Country-specific registration and rules need a separate launch-readiness check.

### 5. Mature-product reference point: configurable, but deliberately restrained

HighLevel allows SMS/email timing, custom interval, maximum retries, and stops retries on that channel after a click; its own guidance says most teams start with 2–3 retries. [HighLevel review-request settings](https://help.gohighlevel.com/support/solutions/articles/48000980328-reputation-management-how-to-customize-the-review-request-messages-sms-email-).

Jobber uses a much more guarded contractor pattern: one review request per client every six months, up to two follow-ups at 3 and 5 days after the initial request, and no initial text from 9 PM to 9 AM local time. [Jobber Reviews](https://help.getjobber.com/en/articles/reviews-marketing-tools/).

**Evidence-led starting point for the later product decision:** one SMS after a contractor-selected completed-work event, then no more than one or two short reminders; stop at click, response, private feedback, known review, opt-out, failed delivery, cancellation, or an open recovery issue. The exact cap is a UCRM product choice, not a number imposed by Google—but 5–12 repeated nudges across a month should not be offered in the first campaign design.

## What remains possible today vs. what waits for Google approval

| Available with copied official Google link | Waits for Google API approval + each contractor's OAuth consent |
| --- | --- |
| Manual and automatic eligible review requests; SMS-first sequence; contractor branding and templates; consent/opt-out controls; click tracking; private feedback open to all; recovery alerts; campaign history | Google profile discovery/one-click selection; automatic review import and matching; live rating/review dashboard; publishing or editing Google replies; dependable automatic stop on a newly posted Google review |

## Sources checked

- [Google Maps User Generated Content Policy](https://support.google.com/contributionpolicy/answer/7400114?hl=en)
- [Google: create a review link or QR code](https://support.google.com/business/answer/16816815?hl=en)
- [Google Business Profile API prerequisites](https://developers.google.com/my-business/content/prereqs)
- [Google OAuth implementation](https://developers.google.com/my-business/content/implement-oauth)
- [Google review-data API guide](https://developers.google.com/my-business/content/review-data)
- [UK CMA fake reviews guidance (CMA208)](https://assets.publishing.service.gov.uk/media/67eeb64fe9c76fa33048c790/CMA208_-_Fake_reviews_guidance.pdf)
- [FTC: Soliciting and paying for online reviews](https://www.ftc.gov/business-guidance/resources/soliciting-paying-online-reviews-guide-marketers)
- [Twilio A2P 10DLC overview](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc)
- [Twilio Compliance Toolkit](https://www.twilio.com/docs/messaging/features/compliance-toolkit)
- [HighLevel review-request settings](https://help.gohighlevel.com/support/solutions/articles/48000980328-reputation-management-how-to-customize-the-review-request-messages-sms-email-)
- [Jobber Reviews](https://help.getjobber.com/en/articles/reviews-marketing-tools/)
- [ICO PECR electronic-marketing guidance](https://ico.org.uk/for-organisations/direct-marketing-and-privacy-and-electronic-communications/guidance-on-direct-marketing-using-electronic-mail/how-do-we-comply-with-the-pecr-electronic-mail-marketing-rules/)
- [CRTC CASL FAQ](https://crtc.gc.ca/eng/com500/faq500.htm)

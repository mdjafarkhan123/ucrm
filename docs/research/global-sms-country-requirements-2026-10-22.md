# Global two-way SMS: country requirements for a Twilio ISV (US, CA, AU, NZ, BR, UK)

Research date: 2026-10-22
Scope: What Uplift Contractor (Twilio ISV, one subaccount + Messaging Service per contractor organization) must do so a
local contractor can **send and receive** SMS/MMS with its own customers in six countries. Builds on
[ghl-jobber-sms-onboarding-plan.md](ghl-jobber-sms-onboarding-plan.md) (US 10DLC product shape) and
[communications-a2-stage3-transport-webhooks.md](communications-a2-stage3-transport-webhooks.md) (transport/webhooks); those
facts are not repeated here.
Evidence labels: **Fact** = stated in a cited primary source. **Live check** = read-only Twilio API call made from our parent
account on 2026-10-22 (no resources created, no money spent). **Inference** = conclusion drawn from facts. **Not found** =
searched, no primary source located. Prices are "published price on 2026-10-22" unless stated; Twilio says prices "may change
without notice".
Not legal advice.

## Plain-English summary

| Country | Two-way SMS realistic for one contractor? | Number type to sell | Before the number can be bought | Before texts flow | MMS | What our app must add |
| --- | --- | --- | --- | --- | --- | --- |
| United States | Yes | Local (10DLC) — today's path; toll-free as an alternative | Nothing (no bundle) | A2P 10DLC Brand + Campaign (local) **or** Toll-Free Verification (toll-free) | Yes | Already built for 10DLC; add toll-free + TFV path for businesses that can't pass 10DLC |
| Canada | Yes | Local or toll-free | Nothing (no bundle) | Canadian numbers texting Canadians: **no 10DLC**. Toll-free needs TFV. If the contractor also texts US customers, 10DLC applies to that US traffic | Yes | Allow `CA` without forcing 10DLC; offer toll-free + TFV (Twilio's recommended A2P route in Canada) |
| Australia | Yes | **Mobile** (+614) — the only SMS-capable AU type | Regulatory Bundle (business: name + business ID number, registry extract, proof of address; address may be anywhere for mobile) | No registration for numbers. Alphanumeric IDs must be on ACMA register (one-way only, optional) | Yes (AU mobile, some numbers) | Regulatory Bundle flow with document upload; AU mobile purchase; Spam Act consent text |
| United Kingdom | Yes | **Mobile** (+447) — the only SMS-capable UK type | Regulatory Bundle (business: name, registration authority + number, website, address, authorised rep; mobile address may be anywhere) | Nothing further for long codes | No (converted to link) | Regulatory Bundle flow; MMS Converter; PECR consent rules |
| New Zealand | **No, not with a phone number.** Only a dedicated short code (5–6 weeks; reclaimed below 1,000 msgs / 60 days) | None for SMS (Twilio NZ local/toll-free are voice-only) | — | — | No | Mark SMS unavailable; offer WhatsApp instead |
| Brazil | **No, not with a phone number.** Domestic long codes are P2P-only; Twilio BR local numbers are voice-only. Short code only (2–4 weeks) | None for SMS | (Voice numbers need a Brazil CNPJ + Brazilian address) | — | No | Mark SMS unavailable; offer WhatsApp instead |

**Answers to the two confirmation questions**

- **Bangladesh ISV primary profile:** No Twilio source found that rejects a Bangladesh-registered ISV primary profile for
  these flows. The ISV flows require an *approved* Primary Customer Profile with business identity "ISV, Reseller, or
  Partner" (we have one, approved 2026-10-19). In every country's bundle/registration, the **end user is the contractor**,
  not us. One open risk: Twilio's new-Console ISV A2P guide lists "Businesses headquartered outside of the US, Canada, EU,
  UK, or Australia" under "This guide isn't intended for" — wording is ambiguous; confirm with Twilio support (see Open
  questions / risks). Sources in §8.
- **Do Canadian numbers need 10DLC?** Not for texting Canadian recipients. 10DLC registration applies to traffic sent from
  US **or Canadian** 10DLC numbers **to US recipients**; Twilio states outbound traffic to Canada is not affected. Sources
  in §2.

---

## 1. United States

**Numbers / two-way / MMS**
- **Fact:** Two-way SMS and MMS supported; domestic long code requires A2P 10DLC registration; toll-free "Requires
  verification"; short code 6–10 weeks; alphanumeric not supported.
  ([Twilio US SMS guidelines](https://www.twilio.com/en-us/guidelines/us/sms))
- **Live check:** `AvailablePhoneNumbers/US` offers `local` and `toll_free`; sampled numbers were SMS, MMS and voice
  capable with `address_requirements: none`.
- **Fact:** US toll-free numbers send/receive SMS and MMS with US and Canada end users.
  ([Twilio: MMS on toll-free](https://help.twilio.com/articles/223133487),
  [Twilio: toll-free SMS](https://help.twilio.com/articles/223181448))

**Bundle / address**
- **Fact:** "Regulatory compliance registrations aren't required for US phone numbers."
  ([Twilio Phone Numbers](https://www.twilio.com/docs/numbers-and-senders/phone-number-senders))
- **Live check:** Regulations API for US local and toll-free returns empty `end_user` and `supporting_document`
  requirements.

**Sender registration**
- Already covered in the earlier note (ISV Secondary Customer Profile → Brand → Campaign).
- **Fact:** A non-US/non-Canada entity can register a Standard Brand only with a government-issued tax ID; Sole Proprietor
  is limited to US/Canada individuals. ([Twilio A2P limitations](https://help.twilio.com/articles/1260804728069),
  [Required info for A2P](https://help.twilio.com/articles/13718729624091))
- **Fact:** Toll-Free Verification (TFV) is required; unverified toll-free numbers are blocked (error 30032). ISVs must
  submit the **end business's** details. Review ~3–5 business days. API: `POST
  https://messaging.twilio.com/v1/Tollfree/Verifications` with `CustomerProfileSid`; a white-label Compliance Embeddable
  (`POST https://trusthub.twilio.com/v1/ComplianceInquiries/Tollfree/Initialize`) needs an approved ISV primary profile and
  access-form registration.
  ([TFV for US/Canada](https://help.twilio.com/articles/5377174717595),
  [TFV for ISVs](https://help.twilio.com/articles/13263383206299),
  [TFV API guide](https://www.twilio.com/docs/messaging/compliance/toll-free/api-onboarding),
  [Compliance Embeddable for TFV](https://www.twilio.com/docs/messaging/compliance/toll-free/compliance-embeddable-onboarding))
- **Fact:** Business Registration Number is mandatory for new TFV submissions from 17 Feb 2026, except `SOLE_PROPRIETOR`
  business type. ([TFV BRN policy](https://help.twilio.com/articles/38266268244507),
  [Error 30527](https://www.twilio.com/docs/api/errors/30527))
- **Inference:** Toll-free + TFV is a second US path for a contractor who has no EIN and can't use Sole Proprietor, or whose
  10DLC campaign keeps failing. It keeps two-way and MMS.

**Content/consent** — covered in the earlier note. **Fact:** Toll-free STOP is also handled by the carrier; Advanced Opt-Out
on toll-free is "not recommended" (duplicate messages risk).
([Long code vs toll-free vs short code](https://help.twilio.com/articles/360038173654))

**Costs (published price on 2026-10-22)** ([US SMS pricing](https://www.twilio.com/en-us/sms/pricing/us),
[A2P fees](https://help.twilio.com/articles/1260803965530), [Campaign vetting](https://help.twilio.com/articles/11587910480155))
- Local $1.15/mo, toll-free $2.15/mo. SMS $0.0083 out / $0.0083 in + carrier fees; MMS $0.022 out.
- 10DLC: Brand $4.50 (Sole Prop / Low-Volume Standard) or $46 (Standard incl. secondary vetting); $15 campaign vetting
  (non-refundable); monthly campaign $2 (Sole Prop), $1.50 (low-volume mixed), $10 (standard).
- TFV fee: **not found** on Twilio's TFV pages.

**GHL:** buys local/toll-free in the sub-account, Persona identity check for +1 numbers, A2P Trust Center, toll-free
verification. A2P fees shown to agencies: $22.50 (Sole Prop / LV) or $64 (HV) one-time, incl. $3 "Fast Track".
([GHL purchase a number, modified 2026-09-18](https://help.gohighlevel.com/support/solutions/articles/155000003226-how-to-purchase-a-phone-number),
[GHL pricing guide, modified 2026-10-12](https://help.gohighlevel.com/support/solutions/articles/48001223556-phone-system-pricing-billing-guide),
[GHL toll-free verification](https://help.gohighlevel.com/support/solutions/articles/48001222300-toll-free-number-verification-guide-for-lc-phone-us-canada-))

## 2. Canada

**Numbers / two-way / MMS**
- **Fact:** Two-way SMS and MMS supported. Long code domestic supported; toll-free supported but "Requires verification";
  short code 12–16 weeks; alphanumeric not supported. Twilio "recommends sending A2P traffic over short codes or verified
  toll-free numbers" because Canadian carriers filter A2P strictly.
  ([Twilio CA SMS guidelines](https://www.twilio.com/en-us/guidelines/ca/sms))
- **Fact:** MMS on CA long code and toll-free, 600 KB, 100% coverage.
  ([Twilio Global MMS](https://help.twilio.com/articles/12557401622811))
- **Live check:** `AvailablePhoneNumbers/CA` offers `local` and `toll_free`, sampled numbers SMS+MMS+voice,
  `address_requirements: none`.

**Bundle / address**
- **Live check:** Regulations API for CA local and toll-free returns no end-user or document requirements. **Fact:** GHL
  states a Regulatory Bundle is not required for US or Canadian numbers
  ([GHL migrate to LC Phone](https://help.gohighlevel.com/support/solutions/articles/48001204027)).

**Sender registration — does 10DLC apply?**
- **Fact:** "This regulation applies **only** to messaging sent from 10DLC numbers to receiving numbers in the US."
  ([Twilio A2P 10DLC in Conversations](https://www.twilio.com/docs/conversations-classic/a2p-10dlc-conversations))
- **Fact:** "Outbound traffic to Canada or any inbound / internal traffic received on A2P 10DLC senders will not be
  impacted." ([Shutdown of unregistered 10DLC](https://help.twilio.com/articles/14910496447771))
- **Fact:** "US and Canadian 10DLC phone numbers must be registered before you can use them to send messages from your
  application to US-based recipients."
  ([Twilio free trial guide](https://www.twilio.com/docs/usage/tutorials/how-to-use-your-free-trial-account))
- **Fact:** Toll-free verification is required to send to the US **and Canada** (same TFV process/API as US).
  ([TFV for US/Canada](https://help.twilio.com/articles/5377174717595))
- **Inference:** A Canadian contractor texting Canadian customers from a Canadian long code needs no 10DLC, but faces heavy
  carrier filtering. A verified Canadian toll-free number is the route Twilio recommends. The CBN (Canadian Business
  Number) is the BRN for TFV.

**Content/consent (CASL)**
- **Fact:** Commercial electronic messages need consent (express, or implied — e.g. purchase within 2 years, inquiry
  within 6 months), sender identification, and a free unsubscribe (a text can offer "STOP"); opt-outs honoured within
  10 business days; identification details valid 60 days. Replies to a recipient's request/inquiry are exempt from consent.
  ([CRTC CASL FAQ](https://crtc.gc.ca/eng/com500/faq500.htm), [CRTC implied consent guidance](https://crtc.gc.ca/eng/com500/guide.htm))
- Quiet hours for SMS: **not found** (Twilio only says daytime unless urgent).
- **Fact:** Restricted content includes cannabis, CBD, alcohol, high-risk finance, firearms.
  ([Twilio CA SMS guidelines](https://www.twilio.com/en-us/guidelines/ca/sms))

**Costs (published price on 2026-10-22)** ([CA SMS pricing](https://www.twilio.com/en-us/sms/pricing/ca))
- Long code $1.15/mo, toll-free $2.15/mo. SMS $0.0083 out / $0.0083 in; MMS $0.022 out / $0.0165 in (long code).
- Carrier fees per message, e.g. Bell & Virgin $0.0087, Rogers $0.0084, Telus $0.0073, others $0.0064 (first column on
  page; the page doesn't label which column is SMS vs MMS clearly).

**GHL:** Canada handled exactly like the US in LC Phone (local/toll-free, Persona for +1, TFV); same per-segment price as US.
([GHL pricing guide](https://help.gohighlevel.com/support/solutions/articles/48001223556-phone-system-pricing-billing-guide))

## 3. Australia

**Numbers / two-way / MMS**
- **Fact:** Two-way SMS and MMS supported; long code domestic and international supported, no pre-registration; short
  code "Not supported" by Twilio; alphanumeric must be pre-registered (5 business days); dynamic alphanumeric banned since
  25 Apr 2023. ([Twilio AU SMS guidelines](https://www.twilio.com/en-us/guidelines/au/sms))
- **Live check:** `AvailablePhoneNumbers/AU` offers `local`, `mobile`, `toll_free`. **Only `mobile` numbers were SMS
  capable** (20/20); half of the sampled mobiles were MMS capable. Local and toll-free samples were voice-only.
- **Fact:** AU MMS on long code inbound and outbound, 1 MB, 100% coverage; delivery receipts Optus only.
  ([Twilio Global MMS](https://help.twilio.com/articles/12557401622811))

**Regulatory Bundle (AU Mobile)**
- **Live check (Regulations API, `IsoCountry=AU&NumberType=mobile`):**
  - *Business:* end-user field `business_name`; documents: business name proof (`commercial_registrar_excerpt`),
    business address proof (registry extract, utility bill, tax document, rental receipt or title deed — "May be anywhere
    in the world"), business ID number (`commercial_registrar_excerpt`).
  - *Individual:* name + government ID/passport; address proof "Must be within Australia".
- **Fact:** Guidelines page agrees: mobile businesses may use an address anywhere; AU local needs an Australian address,
  ABN/ACN, ASIC extract, authorised rep ID, possibly an LOA; ISVs must state whether they assign numbers to end customers.
  ([Twilio AU regulatory guidelines](https://www.twilio.com/en-us/guidelines/au/regulatory))
- **Fact:** Under ACMA's Scam Prevention Framework, KYC for AU local, mobile and toll-free is being tightened; final rules
  not yet issued. Review "up to five business days". Bundle is attached via the IncomingPhoneNumber `BundleSid`. Twilio
  points ISVs to the Compliance Embeddable.
  ([Twilio: KYC in Australia](https://help.twilio.com/articles/49291010297883))

**Sender registration**
- **Fact:** From **1 July 2026**, every alphanumeric sender ID used in Australia must be on ACMA's Sender ID Register;
  unregistered IDs show as "Unverified". ISVs either let Twilio register for them (as the certified telco) or register
  directly. Registration is per account/subaccount, one at a time, done in Console; ~2 weeks after reaching ACMA. Documents:
  company extract, proof linking brand to ID, officer ID or rep ID + LOA.
  ([Twilio: register AU alphanumeric](https://help.twilio.com/articles/47624808819483),
  [Twilio: AU Sender ID regulatory info](https://help.twilio.com/articles/46266521342747))
- **Fact:** Sender IDs can't be numbers-only ([ACMA, via search result summary of SMS Sender ID Register page](https://www.acma.gov.au/sms-sender-id-register)).
  Direct read of ACMA pages failed (timeout), so ACMA's own statement on phone-number senders is **not found**; Twilio's
  AU guideline says long codes don't need pre-registration.
- API for AU alphanumeric registration: **not found** (Console only per Twilio article).
- **Inference:** Two-way needs the AU mobile number; the alphanumeric register only matters if we later add one-way branded
  sends.

**Content/consent**
- **Fact (Twilio summary of Spam Act 2003):** consent, sender identification (name + contact details), and a low/no-cost
  unsubscribe for commercial messages; daytime sending.
  ([Twilio AU SMS guidelines](https://www.twilio.com/en-us/guidelines/au/sms))

**Costs (published price on 2026-10-22)** ([AU SMS pricing](https://www.twilio.com/en-us/sms/pricing/au))
- Mobile number $8.25/mo. SMS $0.0515 out / $0.0075 in; MMS $0.35. Alphanumeric free. No bundle fee found.

**GHL:** AU local numbers need a Business-type bundle created in the client's sub-account (individual not supported);
ASIC/ABN extract, Australian street address proof, website, rep ID, authority proof; 1–3 business days; deadline 1 July
2026 with "no grace period"; unlinked numbers stop working and may be reclaimed. Mobile/toll-free guidance "published
separately". ([GHL AU regulatory bundle, modified 2026-06-02](https://help.gohighlevel.com/support/solutions/articles/155000008023-how-to-create-and-link-a-regulatory-bundle-for-australian-local-numbers))
GHL lists AU MMS at $0.35. ([GHL pricing guide](https://help.gohighlevel.com/support/solutions/articles/48001223556-phone-system-pricing-billing-guide))

## 4. United Kingdom

**Numbers / two-way / MMS**
- **Fact:** Two-way SMS supported; domestic long code supported; **international long code not supported** (foreign
  numbers can't reach UK handsets); short code 8–12 weeks; dynamic alphanumeric supported (one-way); MMS "Converted to SMS
  with an embedded URL". ([Twilio UK SMS guidelines](https://www.twilio.com/en-us/guidelines/gb/sms))
- **Fact:** UK local SMS-enabled numbers are domestic only; UK **mobile** numbers work domestically and internationally.
  ([Can I use my Twilio number for SMS?](https://help.twilio.com/articles/223133887))
- **Live check:** `AvailablePhoneNumbers/GB` offers `local`, `mobile`, `toll_free`; **only mobile samples were SMS
  capable** (none MMS); local and toll-free samples were voice-only.

**Regulatory Bundle**
- **Fact:** Since 27 May 2024 every new UK long code purchase needs an approved RC bundle; since 30 Sep 2024 all UK long
  codes (local, national, mobile, toll-free) must be on one; non-compliant numbers at risk of blocking. No fee. A business
  not registered in the UK should use UK mobile or toll-free; an unregistered business uses an individual bundle. Each
  number goes on the bundle of its owner (by business name).
  ([Twilio: UK KYC](https://help.twilio.com/articles/21038555454875))
- **Live check (Regulations API, GB mobile, business):** end-user fields `business_name`,
  `business_registration_identifier`, `business_registration_number`, `business_website`, `first_name`, `last_name`,
  `phone_number`, `email`, `business_identity`, `is_subassigned`, `comments`; one `business_address` item ("May be anywhere
  in the world; a PO Box is not acceptable"). GB local requires a UK address. Individual: name + ID/passport + address.
- **Fact:** The rep phone "cannot be a number which you've acquired from a CPaaS provider such as Twilio."
  ([Twilio UK regulatory guidelines](https://www.twilio.com/en-us/guidelines/gb/regulatory))
- Review time: **not found** for UK specifically; Twilio's general bundle article says up to 2–3 business days
  ([How to submit a bundle](https://help.twilio.com/articles/8338625205147)).

**Sender registration:** none for long codes beyond the bundle. Alphanumeric: only "Protected" (MEF/BT) IDs need
pre-registration; generic IDs blocked. ([Twilio UK SMS guidelines](https://www.twilio.com/en-us/guidelines/gb/sms))

**Content/consent (PECR, ICO)**
- **Fact:** Marketing texts to individuals need specific, positive-action consent; "soft opt-in" for existing customers'
  similar products if an opt-out was offered at collection and in every message. Sole traders count as individuals.
  ([ICO electronic mail marketing](https://ico.org.uk/for-organisations/direct-marketing-and-privacy-and-electronic-communications/guide-to-pecr/electronic-and-telephone-marketing/electronic-mail-marketing/))
- Cannabis content prohibited; daytime sending. ([Twilio UK SMS guidelines](https://www.twilio.com/en-us/guidelines/gb/sms))

**Costs (published price on 2026-10-22, "current as of October 2026")** ([UK SMS pricing](https://www.twilio.com/en-us/sms/pricing/gb))
- Mobile number $2.50/mo (local $1.15/mo but voice-only). SMS $0.056 out / $0.0075 in. Short code $1,667/mo.

**GHL:** UK long code for two-way, created via Settings → Phone System → Regulatory Bundle / Address, linked to the number;
alphanumeric for one-way; sending to UK from US numbers "isn't supported" (error 21612).
([GHL UK & Turkey compliance, modified 2026-09-04](https://help.gohighlevel.com/support/solutions/articles/48001240411-action-required-international-sms-compliance-updates-uk-turkey))

## 5. New Zealand

**Numbers / two-way**
- **Fact:** "Mobile operators require Dedicated Short Codes"; alphanumeric and domestic long code "Not supported";
  international long code delivers but sender ID not preserved; short code 5–6 weeks. Every message must include "Reply to
  this SMS will be charged." MMS converted to link.
  ([Twilio NZ SMS guidelines](https://www.twilio.com/en-us/guidelines/nz/sms))
- **Live check:** `AvailablePhoneNumbers/NZ` offers only `local` and `toll_free`; **no sampled number was SMS capable**.
- **Fact:** NZ short codes can be pulled if usage stays below 1,000 messages for 60 days; must follow TCF standards.
  ([Twilio NZ short code best practices](https://help.twilio.com/articles/1260800614149))
- **Inference:** Two-way SMS for one NZ contractor is not realistic: a dedicated short code per business takes 5–6 weeks
  and a small contractor would fall under the usage floor. Short-code price: **not found** (NZ pricing page lists only
  "International Numbers").

**Bundle (voice numbers only):** NZ local business bundle = business name + registry/registration document + address proof
(anywhere, no PO box). (Live check + [Twilio NZ regulatory guidelines](https://www.twilio.com/en-us/guidelines/nz/regulatory))

**Content/consent (UEMA 2007, DIA):** consent (express/inferred/deemed, sender bears proof), accurate sender
identification, free functional unsubscribe honoured within 5 working days.
([DIA: three steps](https://www.dia.govt.nz/Spam-Three-Steps), [UEMA 2007](https://www.legislation.govt.nz/act/public/2007/0007/latest/whole.html))

**Costs:** SMS out $0.105 via international numbers (published price on 2026-10-22).
([NZ SMS pricing](https://www.twilio.com/en-us/sms/pricing/nz))

**GHL:** NZ-specific SMS support **not found** in GHL help.

## 6. Brazil

**Numbers / two-way**
- **Fact:** Domestic long code "Limited to person-to-person (P2P) messaging"; international long code not supported by
  operators (sender may be replaced by a random number); short code supported, 2–4 weeks; alphanumeric pre-registration
  optional (~10 weeks, TIM/Claro/Vivo); dynamic alphanumeric not supported; MMS converted to link.
  ([Twilio BR SMS guidelines](https://www.twilio.com/en-us/guidelines/br/sms))
- **Live check:** `AvailablePhoneNumbers/BR` offers only `local`; sampled numbers voice-only, `address_requirements: local`.
- **Fact:** BR voice numbers need a CNPJ, registry excerpt and a Brazilian address (no PO box).
  ([Twilio BR regulatory guidelines](https://www.twilio.com/en-us/guidelines/br/regulatory))
- **Inference:** Two-way SMS from a normal number is not possible through Twilio. Only a short code (2–4 weeks, price
  **not found**) could do it. Twilio says two-way works where it offers "SMS-capable phone numbers or short codes"
  ([Twilio two-way SMS](https://help.twilio.com/articles/235288367)).

**Content/consent:** marketing banned outside 09:00–22:00 local and all Sunday; no political-electoral, contests, telecom
promotions. ([Twilio BR SMS guidelines](https://www.twilio.com/en-us/guidelines/br/sms),
[BR short code best practices](https://help.twilio.com/articles/4425028701467)). Anatel/LGPD primary text for SMS:
**not found** (not researched to the regulator).

**Costs:** SMS $0.0599 (published price on 2026-10-22, "current as of October 2026").
([BR SMS pricing](https://www.twilio.com/en-us/sms/pricing/br))

**What GHL does instead:** WhatsApp. GHL documents a WhatsApp restriction: businesses outside Brazil can't message users in
Brazil, and businesses in Brazil can only message users in Brazil ("no workaround… from our side"); article states
"effective September 15" without a year.
([GHL: restricted from messaging users in this country](https://help.gohighlevel.com/support/solutions/articles/155000007285-error-business-account-is-restricted-from-messaging-users-in-this-country))
**Inference:** A Brazilian contractor messaging Brazilian customers on WhatsApp fits inside that restriction.
**Fact:** Twilio's WhatsApp ISV path is Meta's Tech Provider program: the customer runs Embedded Signup, creates a WABA, we
connect it to their subaccount with the Senders API; joining takes ~3–4 weeks.
([Twilio Tech Provider program](https://www.twilio.com/docs/whatsapp/isv/tech-provider-program),
[Register WhatsApp senders – ISVs](https://www.twilio.com/docs/whatsapp/isv/register-senders))

## 7. How ISVs create bundles by API (all bundle countries)

- **Fact:** v2 Regulatory Compliance flow: read the Regulation (`IsoCountry`, `NumberType`, `EndUserType`, ideally
  `IncludeConstraints=true`) → create Bundle (`FriendlyName`, `Email`, optional `StatusCallback`) → create End-User and
  Supporting Documents (file upload, JPEG/PNG/PDF up to 5 MB) → Item Assignments → Evaluations (instant error feedback) →
  submit (`pending-review`). Statuses: `draft`, `pending-review`, `in-review`, `twilio-rejected`, `twilio-approved`. Twilio
  says "Regulations can and do change. Please make sure not to hardcode any regulation."
  ([Getting started: RC REST APIs](https://www.twilio.com/docs/phone-numbers/regulatory/getting-started/create-new-bundle-public-rest-apis),
  [RC API overview](https://www.twilio.com/docs/phone-numbers/regulatory/api),
  [Error 22217](https://www.twilio.com/docs/api/errors/22217))
- **Fact:** Buying a number takes `BundleSid` and `AddressSid` on `POST /IncomingPhoneNumbers` (also per-type `Local`,
  `Mobile`, …). (Twilio API reference, `CreateIncomingPhoneNumber` operation via Twilio docs search)
- **Fact:** Bundle **Copies** let you update a bundle when regulations change while the original stays approved; **Clones**
  copy a `twilio-approved` bundle into another account in the same organization, arriving approved.
  ([Bundle Copies](https://www.twilio.com/docs/phone-numbers/regulatory/api/copies-resource),
  [Bundle Clones](https://www.twilio.com/docs/phone-numbers/regulatory/api/clones-resource),
  [Compliance info update guide](https://www.twilio.com/docs/phone-numbers/regulatory/getting-started/api-getting-started-compliance-information-update))
- **Fact:** Review "up to two/three business days" generally; AU "up to five business days"; rejections carry reasons and
  can be edited and resubmitted. ([Submit a bundle](https://help.twilio.com/articles/8338625205147),
  [Bundle rejections](https://help.twilio.com/articles/16066152436507), [AU KYC](https://help.twilio.com/articles/49291010297883))
- **Inference:** For our architecture the bundle is created **inside the contractor's subaccount** with that contractor as
  the End-User (`is_subassigned` / ISV question answered "yes"); clones are only useful if one contractor gets several
  subaccounts.

## 8. Bangladesh ISV primary profile — evidence

- **Fact:** TFV and the TFV Compliance Embeddable require "a Trust Hub Primary Customer Profile for a business whose Business
  Identity is set to ISV or Reseller"; trial accounts ineligible.
  ([TFV Compliance Embeddable](https://www.twilio.com/docs/messaging/compliance/toll-free/compliance-embeddable-onboarding))
- **Fact:** ISV A2P needs a `Twilio Approved` Primary Business Profile with "ISV Reseller or Partner".
  ([ISV Standard/LVS API guide](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc/onboarding-isv-api))
- **Fact:** Bundles, TFV and AU sender IDs must carry the **end business's** information when an ISV sub-assigns.
  ([TFV for ISVs](https://help.twilio.com/articles/13263383206299), [AU alphanumeric](https://help.twilio.com/articles/47624808819483))
- **Not found:** any Twilio rule excluding a Bangladesh (or any non-US) ISV primary profile from these flows.
- **Ambiguity:** Twilio's new-Console "ISV A2P 10DLC Registration Guide" lists "Businesses headquartered outside of the US,
  Canada, EU, UK, or Australia" under "This guide isn't intended for", while the Direct guide lists the same text under
  "intended for". It is unclear whether this refers to the ISV or its customers.
  ([ISV A2P guide](https://help.twilio.com/articles/53502193289755),
  [Direct guide](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc/direct-standard-onboarding))

## What the app needs (cross-country)

Today: `sms-registration.ts` hardcodes `US`/`long_code`; `trust-hub-submission.ts` maps only US/CA and only 10DLC; there
is no number-search/purchase code and no Numbers v2 Regulatory Compliance (bundle) code in `src/lib/server`.

1. **Country capability table (server-side, one place).** Per country: SMS sender type to sell (US/CA local or toll-free;
   AU/GB mobile; NZ/BR none), MMS yes/no, bundle needed yes/no, sender registration (10DLC, TFV, none), consent rule set,
   fallback channel. Verified at runtime against `AvailablePhoneNumbers` capabilities (`SmsEnabled=true`) rather than
   trusted blindly.
2. **Number search and purchase by country and type** (`Local`, `Mobile`, `TollFree`) with `SmsEnabled`/`MmsEnabled`
   filters, passing `BundleSid`/`AddressSid` where required; show monthly price per country.
3. **Regulatory Bundle flow** (AU, UK, and any later country): fetch the Regulation live, render its fields and document
   choices, upload documents (PDF/JPG/PNG ≤5 MB), run Evaluations before submit, track status by `StatusCallback` +
   polling, show rejection reasons, edit-and-resubmit, and later Bundle Copy when Twilio flags "information update
   required". Alternatively pilot Twilio's Compliance Embeddable (needs access request).
4. **Address and identity collection** that is country-aware: business registration authority + number (EIN, CBN, ABN/ACN,
   UK Companies House, CNPJ), registry extract upload, authorised-representative ID, LOA where the rep isn't an officer,
   proof of address, and rules like "no PO box" and "rep phone can't be a Twilio number".
5. **Toll-free verification path** (US and CA) via the TFV API, including BRN fields, opt-in image URLs, sample message,
   status tracking and resubmission.
6. **10DLC country gate fix:** 10DLC only when the sending number is US/CA **and** recipients include the US; a Canadian
   contractor texting only Canadians shouldn't be forced through it.
7. **Per-country consent and footer rules:** opt-out wording in the local style (STOP etc.), Spam Act / CASL / PECR / UEMA
   consent evidence, Brazil marketing hours (09:00–22:00, not Sunday), "daytime unless urgent" quiet-hours option per
   recipient time zone, and toll-free's carrier-level STOP handling.
8. **MMS fallback:** turn on MMS Converter so photos to UK (and anywhere MMS isn't supported) arrive as a link instead of
   failing; tell the user in the composer.
9. **Recipient-country routing guard:** send only from a same-country sender (UK blocks foreign long codes; US/CA numbers to
   UK fail with 21612); show an actionable error.
10. **"SMS not available here" state + WhatsApp fallback** for NZ and BR (WhatsApp Tech Provider onboarding, Senders API
    per subaccount).
11. **Per-country pricing and fees** in the usage ledger (number rental differs: $1.15 US/CA, $2.50 UK mobile, $8.25 AU
    mobile; segment prices differ ~7×).

## Open questions for Jafar (product choices only)

1. **Which countries at launch?** Recommendation: US + Canada first (no paperwork to buy a number), then UK and Australia
   (need the document-upload bundle flow), and treat NZ/Brazil as "WhatsApp only".
2. **Canada sender type:** should Canadian contractors get a toll-free number by default (what Twilio recommends because
   Canadian carriers filter local numbers) or a local number that looks familiar to customers? Recommendation: toll-free
   default, local as an option.
3. **Offer toll-free in the US too?** It rescues contractors who can't pass 10DLC, but customers may trust a local area code
   more. Recommendation: offer it as the fallback, not the default.
4. **NZ and Brazil:** are we happy to tell those contractors "texting isn't available in your country — use WhatsApp", or
   should we pay for a dedicated short code for larger customers? Recommendation: WhatsApp only.
5. **Who uploads the documents?** Contractor uploads in our app (our own form), or we try Twilio's white-label Compliance
   Embeddable pilot (less for us to build, but needs Twilio access and gives less control over the look).
6. **Pricing per country:** AU mobile numbers cost ~7× a US number per month and AU/UK texts ~7× a US text. Pass through
   per country, or one flat price?

## Risks / things to confirm with Twilio support

- Whether the "headquartered outside US, Canada, EU, UK, or Australia" line in the ISV A2P guide affects a Bangladesh ISV.
- Australia's Scam Prevention Framework KYC changes for mobile numbers are still pending final rules (Twilio, as of this
  date).
- Live checks show what our account can buy today; inventory and capabilities can change.

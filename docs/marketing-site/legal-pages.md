# Legal pages for upliftcontractor.com

Text for the marketing website's three legal pages. Old wording is kept; new or changed parts are marked
**[new]** or **[changed]** so the website editor can see what moved (remove the markers when publishing).
Drawings: `concept.pen`, Marketing row, boards "Website · Privacy Policy" and "Website · Data deletion".

Why it changed: Meta's App Review for Messenger needs a privacy policy that says what Facebook data we
collect, why, and how to ask for its deletion, plus a deletion page or callback URL
([Meta privacy policy expectations](https://developers.facebook.com/documentation/development/terms-and-policies/privacy-policy.md),
[data deletion callback](https://developers.facebook.com/docs/development/create-an-app/app-dashboard/data-deletion-callback)).
Facts below match the code on 2026-10-23: Page key stored encrypted and deleted on disconnect
(`src/lib/server/communications/messenger-connections.ts`), attachments counted but not copied, no automated replies.

Pages and addresses:

| Page | Address | Goes in Meta App Dashboard |
| --- | --- | --- |
| Privacy Policy | `https://upliftcontractor.com/privacy` (exists) | Privacy Policy URL |
| Data deletion | `https://upliftcontractor.com/data-deletion` (new) | User data deletion → Data deletion instructions URL |
| Terms & Conditions | `https://upliftcontractor.com/terms` (exists) | Terms of Service URL |

Footer links on every page: Privacy Policy · Terms & Conditions · **Data deletion [new]** · Contact.

---

## Privacy Policy

Eyebrow: Legal · **Last updated: 23 October 2026 [new]**

Intro: This policy explains how Uplift Contractor handles information connected with this website, our platform,
and our services.

### Who we are

Uplift Contractor is a contractor CRM and marketing platform operated by Jafar Khan. You can contact us at
info@upliftcontractor.com or +8801834969563.

**[new]** Businesses use our platform to talk with their own customers. When they do, the business decides what
it collects about its customers and why, and we handle that information on the business's behalf and on its
instructions.

### Information we collect

Depending on how you use our services, we may collect:

- Contact details, such as name, business name, email address, phone number, and message content that you
  provide.
- Account, form, CRM, customer, job, quote, invoice, and communication information entered into the platform by
  you or an authorized user.
- **[new]** Facebook Messenger information, when a business connects its Facebook Page. See "Facebook Messenger
  information" below.
- Payment-status information related to a transaction. Payment-card details are entered directly on Stripe's
  secure payment page and are not stored by Uplift Contractor.
- Technical and security information needed to protect and operate the website and services, such as IP address,
  device/browser information, and security or spam-check records.

### How we use information

We use information to provide and support the platform; respond to requests; manage accounts, forms,
communications, and payments; protect our services; meet legal obligations; and improve the reliability of our
operations.

We do not use Google Analytics, advertising pixels, PostHog, Hotjar, or similar visitor-tracking tools on this
website. **[new]** We do not sell personal information.

### Facebook Messenger information **[new section]**

A business can connect its Facebook Page to our platform so its staff can read and answer Messenger messages in
one inbox.

**What we receive from Meta**

- When a business connects a Page through Facebook Login: the Page's name and ID, the permissions the business
  granted, and a Page access key. We store the key encrypted.
- When someone messages a connected Page: the sender's Page-scoped ID (a number Meta gives each person for that
  Page only), the message text, the time it was sent, details of any attachment, and whether the business's
  replies were delivered and seen.
- The sender's name and profile photo, only when Meta allows us to read them. Until then the person shows as
  "Facebook user".
- Replies the business's staff send from our platform or from the Page's own Facebook inbox.

**How we use it**

We use this information only to show the business its Messenger conversations, send the replies its staff write,
show whether a reply was delivered and seen, and keep the Page connection working. Replies are written by people;
we do not send automated Messenger replies.

We do not sell Messenger information, use it for advertising, or share it with anyone except the service
providers needed to run the platform. We follow Meta's Platform Terms and Developer Policies.

**How long we keep it**

- When a business disconnects its Page, new messages stop arriving and we delete the Page access key straight
  away. Earlier conversations stay in that business's records, as its other customer records do, until the
  business deletes them or asks us to.
- A business can also remove our access from Facebook at any time: Facebook Settings → Business Integrations →
  Uplift Contractor → Remove.
- To have Messenger information deleted, follow the steps on our Data deletion page
  (upliftcontractor.com/data-deletion).

### Service providers

We use service providers to operate our services. Depending on the feature used, these include:

- Supabase for accounts, forms, and customer information.
- Cloudflare for website protection, spam checking, network delivery, and file storage.
- **[changed]** Brevo and Amazon Web Services (Amazon SES) for platform emails and CRM email communications.
- **[new]** Twilio for text messages that businesses send and receive through the platform.
- **[new]** Meta Platforms for Facebook Messenger messages, when a business connects a Facebook Page.
- Stripe for online payments when that feature is used.
- Mapbox for map and address features where needed.

We may update our service providers as our services change and will update this policy before a new provider
begins handling real visitor or customer information where that update is required.

### SMS privacy and choices

Text messaging is not currently active for Uplift Contractor. If we activate the Uplift Contractor SMS Program, SMS
consent will be optional and will not be a condition of purchase. We will not sell or share SMS consent or
phone-number information with third parties or affiliates for their marketing or promotional purposes.

When the program is active, opted-in users may receive account, support, appointment, service, and promotional
messages. Message frequency may vary, and message and data rates may apply. Users can reply STOP to opt out and
HELP for help. See our SMS Program Terms for the complete program rules.

### Retention and security

We retain information for as long as reasonably needed to provide the services, meet legal and operational
requirements, resolve disputes, and enforce agreements. We use reasonable administrative, technical, and
organizational safeguards designed to protect information. **[new]** Access keys for connected services, such as
Facebook Pages, are stored encrypted. No method of transmission or storage is completely secure.

### Your choices and requests

You may ask about access to, correction of, or deletion of personal information we hold about you, subject to
applicable law and our legitimate operational needs. You may also withdraw an optional SMS consent at any time by
replying STOP once SMS is active. To make a request, contact info@upliftcontractor.com.

**[new]** To delete information that came from Facebook Messenger, see our Data deletion page. We answer every
request within 30 days.

### Changes to this policy

We may update this policy when our data practices or services change. We will publish the updated version on
this page **[new]** and change the "Last updated" date at the top.

---

## Data deletion **[new page]**

Eyebrow: Legal · Last updated: 23 October 2026

Title: Data deletion

Intro: How to ask Uplift Contractor to delete information we received through Facebook Messenger or any other
part of our services.

### If you messaged a business on Facebook

When you message a business's Facebook Page and that business uses Uplift Contractor, your messages are stored
in that business's inbox on our platform. To have them deleted:

1. Email info@upliftcontractor.com with the subject "Data deletion request".
2. Tell us the name of the Facebook Page you messaged, the name on your Facebook account, and roughly when you
   messaged it.
3. We confirm your request by email, delete your Messenger messages and the Page-scoped ID linked to them, and
   tell the business we have done so.

You can also ask the business directly; it can delete your conversation from its inbox.

### If your business connected a Facebook Page

1. In Uplift Contractor, go to Settings → Communications → Messenger and choose Disconnect. New messages stop
   and we delete the Page access key straight away.
2. To remove our access from Facebook too: Facebook Settings → Business Integrations → Uplift Contractor →
   Remove.
3. To delete the conversations already in your inbox, delete them in the app or email info@upliftcontractor.com
   from your account's email address.

### Any other information

To ask about, correct, or delete any other personal information we hold, email info@upliftcontractor.com.

### What happens next

- We reply within 3 business days to confirm we received your request, and finish within 30 days.
- We may ask you to confirm who you are, so that nobody else can delete your information.
- We may keep a small record that the request was made and completed, and anything the law requires us to keep.

Questions: info@upliftcontractor.com · +8801834969563

---

## Terms & Conditions

Eyebrow: Legal · **Last updated: 23 October 2026 [new]**

Intro: These terms govern use of the Uplift Contractor website, platform, and related services.

### Services and accounts

Uplift Contractor provides website, CRM, marketing, communication, and related services for contractors and home
service professionals. Service availability, features, fees, and any service-specific terms are described in the
applicable order form, plan, or agreement.

You are responsible for providing accurate account information, protecting account access, and ensuring that
authorized users act in accordance with these terms.

### Customer responsibilities and acceptable use

You are responsible for the information, contacts, and communications you place in the platform and for having
the permissions and legal basis required to use them. You must comply with applicable law, carrier rules, platform
policies, and the terms of any connected third-party service.

You must not use the services to send unlawful, deceptive, abusive, infringing, fraudulent, or unsolicited
communications; interfere with the services; attempt unauthorized access; or use the services in a way that harms
others or violates applicable requirements.

### Facebook Messenger **[new section]**

If you connect a Facebook Page, you confirm that you are allowed to manage that Page, and you agree to follow
Meta's Terms, Messenger Platform Policy, and Community Standards. Messenger replies are normally allowed only
within 24 hours of the customer's last message; the platform blocks later replies. Promotional messages outside
that window are not allowed. You can disconnect the Page at any time in Settings. How we handle Messenger
information is explained in our Privacy Policy.

### Payments and cancellation

Where payment is required, fees, billing timing, and any renewal terms are presented in the applicable order
form, plan, or agreement. Online payment-card details are entered on Stripe's secure payment page.

To request cancellation or ask about the effective date of a cancellation, contact info@upliftcontractor.com. Any
cancellation is subject to the applicable service agreement and any fees or obligations already due.

### Uplift Contractor SMS Program

Current status: Uplift Contractor text messaging is not active yet. These rules apply if and when the Uplift
Contractor SMS Program is activated.

By checking a separate, optional SMS permission checkbox where a phone number is collected, a user agrees to
receive text messages from Uplift Contractor. Consent is not a condition of purchase or use of services.

- Message types: account, support, appointment, service, and promotional messages.
- Frequency: message frequency may vary.
- Cost: message and data rates may apply.
- Opt out: reply STOP to opt out at any time.
- Help: reply HELP for help, or contact info@upliftcontractor.com or +8801834969563.
- Privacy: SMS consent and phone-number information are not sold or shared with third parties or affiliates for
  their marketing or promotional purposes.
- Carrier notice: carriers are not liable for delayed or undelivered messages.

When the program is active, a user may revoke consent by replying STOP. For information about how we handle data,
see our Privacy Policy.

### Third-party services

Some features use third-party services such as payment processing, email delivery, text messaging, **[changed]**
Facebook Messenger, maps, hosting, security, and data storage. Their availability and terms may affect the related
feature. See our Privacy Policy for the current service-provider information.

### Changes and contact

We may update these terms as the services or applicable requirements change. We will publish the updated terms on
this page **[new]** and change the "Last updated" date at the top. Questions about these terms can be sent to
info@upliftcontractor.com.

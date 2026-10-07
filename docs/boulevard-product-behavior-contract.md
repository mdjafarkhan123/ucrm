# Boulevard-inspired industry editions

**Status:** Planning — overall direction and booking/identity behavior agreed 2026-10-05; clinical-record behavior agreed 2026-10-06; commerce, communications, operations, business-entry, onboarding-program and performance direction settled 2026-10-07; other areas and release scope remain in planning.

## Summary

The platform will provide an industry-appropriate experience for medspas, clinical wellness businesses, salons, barbers, and spas. Medspa & Clinical Wellness is the first expansion priority. Its shared booking and business capabilities are planned alongside its specialist needs. Beauty & Spa follows using shared capabilities. The existing contractor edition continues to follow its own contracts. Boulevard is the primary product reference, with competitors used for focused comparison. The product serves a market rather than one individual business.

## Initial scope approved 2026-10-05

Jafar approved all three initial recommendations:

- US first; other countries remain on the roadmap.
- Boulevard-style booking, forms, consent, charting, and payments define the initial clinical direction. Specialist diagnostic test/report systems are outside the initial promise; any essential gap gets a separate decision.
- Single-location teams first; multi-location capabilities remain in the complete inventory for later planning.

These decisions set boundaries, not final feature-level release approval. Research still inventories the full documented Boulevard landscape.

## Experience and access

The business account selects the relevant industry experience. Its subscription and employees' permissions control the available tools and records. Plan mixed-service business behavior explicitly. Shared tools retain one behavior definition, with differences recorded under the relevant industry. LifeScan is a potential validation example; its subscription does not establish that Boulevard handles every diagnostic task.

The planned top-level experiences are **Contractor**, **Beauty & Spa**, and **Medspa & Clinical Wellness**.
Salon, barbershop and spa are business types within Beauty & Spa rather than separate products. “Clinic” and
“lifecare” do not promise a general healthcare edition: a medical specialty outside the agreed Medspa &
Clinical Wellness boundary needs its own research and scope decision.

One primary industry experience controls a mixed business. Extra services add capabilities without combining
separate products. When a business provides regulated clinical services alongside salon or spa services,
Medspa & Clinical Wellness is normally primary so its stricter record and safety rules remain in force.

## Business entry and onboarding

Agreed by Jafar 2026-10-07. Evidence: [industry onboarding research](research/industry-onboarding-entry-patterns-2026-10-07.md) and [P2H change and publishing research](research/boulevard-business-entry-onboarding-2026-10-07.md). The detailed rules below are our product choices where Boulevard's public guidance is silent.

- Industry-specific marketing pages may speak directly to salons, barbers, spas or medspas, but they feed one
  shared application and purchase journey. The link may preselect a business type and suitable package; it
  does not create a separate onboarding system.
- The initial journey remains assisted: the business applies, Jafar confirms its industry experience,
  business type, package and offsite payment, and only then is its organization created. Provisioning sends a
  secure, organization-specific invitation; there is no reusable public “salon onboarding” or “medspa
  onboarding” link.
- After sign-in, the shared `/setup` destination shows the onboarding program selected for that organization.
  An onboarding program is separate from the package and staff permissions: the industry experience chooses
  the program, purchased capabilities decide which relevant branches appear, and permissions decide who may
  complete or review them.
- Contractor, Beauty & Spa, and Medspa & Clinical Wellness have independently publishable onboarding
  programs. They reuse shared sections such as business identity, branding, team and imports, while keeping
  industry-specific work separate. The current questionnaire becomes the Contractor program; it is not
  duplicated or discarded.
- A business that has started Setup stays on the published program version it started with. A newly published
  version goes to new businesses. Publishing does not reopen a submitted setup. Moving an existing business to
  a newer program requires a Platform Owner review of its completed tasks, saved answers and unfinished work.
  Carry a completed task forward only when its meaning and completion rule still match; preserve earlier
  answers, submissions and times. New or changed required work is shown clearly. A safety-critical change
  receives an explicit affected-business review instead of silently rewriting a live checklist. This approved
  direction replaces the Contractor plan's earlier live-update rule; the current application still needs a
  later build change.
- A change to an existing organization's primary experience is assisted, not inferred from its service names.
  The Platform Owner reviews existing records, purchased capabilities, staff access, unfinished setup and
  clinical readiness, then explicitly approves an in-place transition of the same business account. Existing
  history remains attributable and protected under its original access rules. If those records or safeguards
  cannot be carried safely, the change waits for a supported migration; it does not silently create a second
  account or grant clinical access.
- For a mixed business with an unclear clinical boundary, the assisted application asks for its actual
  services, state and who performs or supervises them. Hold provisioning until the boundary is resolved.
  Confirmed regulated clinical services make Medspa & Clinical Wellness the primary experience, subject to
  its clinical safeguards and the state-specific review required before launch. A salon, spa or laser label
  alone does not decide the experience.
- The Platform Owner edits a draft for one program and previews the exact industry, business type, package
  and staff role, including shown and hidden branches and required completion. The owner tests the journey in
  a safe test organization and sees which businesses a publication or deliberate migration could affect.
  Publication needs an explicit confirmation and creates a fixed version. It does not silently move businesses
  already partway through Setup.

## Performance contract

Jafar approved performance as a build constraint on 2026-10-07, not a cleanup saved for the end.

- Every screen that materially changes a critical journey, payload, hydration work, rendered collection or
  interaction cost, and every path whose cost grows with data, users, requests, subscribers or browser payload,
  completes the project performance design gate before implementation and measured verification after its coherent
  build slice exists.
- Public entry, purchase, sign-in and initial workspace content use server rendering where it reduces the
  first wait. Browser code is reserved for interaction; unavailable industries and capabilities do not ship
  their feature code or assets to that organization. Optional heavy tools load only when needed.
- Global CSS remains the small shared baseline. Component styles stay with their component, and route- or
  industry-specific styles and assets are not placed in the global bundle. Images use appropriately sized
  derivatives and lazy loading outside the first view; versioned static assets use long-lived caching.
- Phone-first screens target Google's “good” Core Web Vitals thresholds: LCP at most 2.5 seconds, INP at most
  200 milliseconds and CLS at most 0.1 at the 75th percentile. Until real-user data exists, a production
  build is tested with representative data under a slowed phone CPU and mobile network and reported as lab
  evidence.
- Verification records route JavaScript and CSS bytes, font and image bytes, request count, server response
  time, database work, rendered-item count and the main interaction timing. It also checks that an industry
  loads only its own navigation and capabilities.
- No registered-user number becomes a capacity promise. Traffic, concurrent sessions, rows per tenant,
  payload, burst length and background work must be exercised before stating capacity.

## Research reference rule

Follow [Reference order and missing behavior](platform-overview.md#reference-order-and-missing-behavior): Boulevard first, then relevant competitors for unresolved gaps, with source attribution and explicit uncertainty.

## Living feature plan

The [public-source inventory](research/boulevard-feature-landscape-2026-10-05.md) records stable identifiers, purposes, sources and availability boundaries. P2 adds detailed workflows, settings, permissions, exceptions and dependencies. P3 will record existing-app suitability, release assignments and completion checks. Area research is linked below.

Track these independently:

| Dimension | Values |
| --- | --- |
| Research confidence | Confirmed / Partly confirmed / Open question |
| Release | Unassigned / Initial release / Later release / Not planned |
| Delivery | Needs research / Planned / In progress / Built, needs verification / Done |

Confirmed means supported by a cited source, not assumed equivalent to our implementation. Done requires verification of the agreed behavior. Research completeness is checked against the official feature catalog, help collections, add-ons, integrations, and release notes, with remaining gaps explicit. Shared journeys must connect end to end.

## Booking and identity

Agreed by Jafar 2026-10-05: every recommendation in round 1 and all twelve proposed defaults. He asked that
smaller follow-up rules be settled by checking how competitors handle them; those are marked **follow-up**.
Each rule names its source: Boulevard, a named competitor where Boulevard is silent or weaker, or **ours**.
Evidence: [P2A research](research/boulevard-booking-identity-2026-10-05.md). Release assignment is P3's job.

### Signing in and client identity

- Clients sign in with a one-time code sent by text or email; there are no passwords. In the medspa edition
  they then confirm their date of birth before seeing any appointment, form or profile detail; a first-time
  client enters it once. Beauty & Spa uses the code alone. *Boulevard.*
- Each business has its own client list. A person who visits two businesses on the platform has a separate
  profile, and a separately saved card, at each. *Ours — Boulevard shares one booking account across its
  businesses; we keep each business's records private to it.*
- In the medspa edition, when one phone or email belongs to several adult profiles, the person cannot pick a
  profile; they are asked to contact the business so each adult gets their own contact details. *Boulevard.*
- Clients can change their name, pronouns, address and message preferences, but not the phone or email they
  sign in with. A date-of-birth change sends the client an alert. *Boulevard.*
- Staff creating a client see a duplicate warning when name, email or phone matches an existing client, and
  must add a phone (child profiles excepted, below). Merging two profiles is permanent, keeps the values staff
  choose, and needs its own permission. Profiles with history cannot be deleted; deletion requests belong to
  operations planning. Staff can block a client from online booking with a reason, and keep one staff-only
  booking alert per client. *Boulevard.*

### Parents and children

- A parent can add their under-age children to their own account, then book, pay and receive messages for
  them. Each child has their own client profile and record. *Hospital patient-portal proxy access (MyChart);
  Vagaro child profiles.*
- The adult age is 18 by default. The business can change it to its state's age of majority — 19 in Alabama
  and Nebraska, 21 in Mississippi ([Cornell LII](https://www.law.cornell.edu/wex/age_of_majority)).
  **Follow-up.**
- A child profile needs no phone or email of its own; messages go to the linked parents. *Follow-up; Jane
  routes a minor's messages to the parent.*
- Online, a parent can add only a new child. Linking a parent to a client already on the business's list, or
  adding a second parent or guardian, is done by staff, and the link is recorded. A child can have more than
  one linked parent or guardian. *Follow-up; Vagaro requires the linked person to accept, Jane notifies the
  patient, and patient portals allow several proxies.*
- In the medspa edition, online booking for an under-age client is done by a linked parent. An under-age
  client who signs in alone is asked to have a parent book or to contact the business. Staff can always book
  them. *Ours, following the parent-proxy pattern.*
- On the child's adult birthday, minor-based parent access ends automatically. Future appointments stay booked,
  and staff get an alert to add the client's own phone or email so they can sign in. An adult may later grant
  separate representative authority; [Clinical records](#clinical-records) defines record access. *HHS
  personal-representative guidance; MyChart proxy transition.*

### May this client book this treatment?

- A service can require an earlier visit — a consultation, good faith exam, patch test or laser test spot —
  and set how long that visit stays valid, the minimum gap before the treatment (for example 48 hours after a
  patch test), and whether both may be booked in the same visit. *Zenoti prerequisites; Phorest patch-test
  period.* A service can also set a minimum age. *Ours — no vendor documents one.*
- A requirement is met once the earlier visit is completed and, where the business requires it, marked passed
  or cleared. How that result is recorded belongs to P2B.
- **Online:** a client who does not meet a requirement cannot book the treatment. Booking offers the required
  visit first, or alongside it when the service allows both together and the minimum gap fits. A client under
  a service's minimum age cannot book it. *Zenoti, Phorest.*
- **Staff:** booking a client who does not meet a requirement shows a warning. Staff with the override
  permission can continue by typing a reason, which is saved in the appointment's history. Which roles hold
  that permission by default belongs to operations planning (P2E). *Zenoti, Phorest; follow-up for the
  permission.*
- Age is checked against the appointment date, so a client can book for a date after their birthday. When the
  date of birth is unknown, staff see an "age unknown" warning; a Beauty & Spa client booking an age-limited
  service online is asked for their date of birth. **Follow-up.**
- If the required visit is later cancelled or not passed, the treatment appointment stays booked but is
  flagged, and staff are alerted. *Phorest and Aesthetic Record: staff-side warnings, never automatic
  cancellation.*
- The calendar shows each appointment's requirement status. *Aesthetic Record good-faith-exam indicator.*

### Services, staff, rooms and open times

- Boulevard's model:
  - Time segments: treatment, processing, finishing and cleanup. The provider is free during processing.
  - Modifiers, and add-ons done by the same provider.
  - Price and length overrides per staff member or role, and a client's personal price or length.
  - Forced service order.
  - Rooms and equipment: one item from each assigned category, held for the whole visit.
  - Published shifts and time blocks, and earliest and latest online booking times.
  - Booked appointments keep the price and length they were booked with.
- Online times avoid leaving awkward small gaps, with a setting to show every time; staff always see every
  time. *Mangomint "avoid gaps"; Boulevard's advanced optimisation is a later option.*
- Improvements over Boulevard: staff get a clear warning before booking outside a shift, over a time block or
  over another appointment; repeating appointments show clashes before saving; a provider with future
  appointments cannot be deactivated until each one is moved or cancelled (Boulevard hides them).

### The appointment journey

- Online booking: choose services → sign-in code → choose a time (held for 30 minutes) → card → deposit if
  required → booked. Requiring a card is a business setting, on by default. *Boulevard flow; Mangomint and
  Vagaro make the card optional.*
- Deposits per service or provider. A cancellation deadline in hours. A late-cancel and no-show fee as a
  percentage or amount, never more than the appointment. Clients change or cancel themselves until the
  deadline, then are asked to contact the business. Client rescheduling keeps the same provider and can be
  switched off. *Boulevard.*
- Statuses: booked, confirmed, arrived, in treatment (optional), completed. Cancellations record a reason
  (mistake, staff, client, late cancel, no-show) and can be restored. Prebooking from checkout; repeating
  appointments are staff-only. *Boulevard.*
- Booking never signs the client up for marketing. *Ours; consent rules belong to P2D.*
- Every guest in a group booking gives their own name and contact before any form or record is created for
  them. *Ours — Boulevard lets guests skip details, which leaves records without an owner.*

### Waitlist

- Clients join a waitlist for a service and provider, with a card if the business requires one; they are not
  charged. Staff can add clients with a note. *Boulevard.* A client can join only for a treatment they could
  book online under the rules above. **Follow-up.**
- Whenever a time opens that matches waitlist entries — a cancellation, a move or a new shift — staff are
  alerted to the matching clients and book one themselves. *Boulevard's waitlist plus an alert of ours;
  Boulevard alerts only on new entries.* Where the alert appears belongs to P2D.
- Automatically offering an opened time to the first client in line, with a deadline to accept, is a later
  option. *Vagaro "First in Line" and "Instant Book".*

### Limits found when checking the build

- **Text codes:** sign-in codes by text come from the platform rather than the business's own number. Twilio
  Verify needs no US texting registration
  ([Twilio](https://www.twilio.com/docs/messaging/compliance/a2p-10dlc)), so a business can offer text codes
  before its own texting is approved. Until the platform's Twilio account is live, codes go by email only.
- **Cards and deposits:** businesses take payment through their own Stripe account, as set out in
  [online payments](online-payments-behavior-contract.md); Stripe shows the card form. Saving a card for
  later charges is not built yet and needs extra permissions on the business's Stripe key. Until a business
  connects Stripe, online booking cannot ask for a card or deposit.
- Holding times, gap avoidance, rooms, requirements and ages run on our own data, with no provider limit.
  Gap avoidance gets a performance design review before it is built.

## Clinical records

Agreed by Jafar 2026-10-06: all four P2B recommendations on parent access, treatment clearance, chart review, and prescribing boundaries. Sources and evidence limits: [P2B clinical research](research/boulevard-clinical-records-2026-10-06.md). These rules describe Medspa & Clinical Wellness behavior; P3 assigns release timing and checks existing-app suitability.

### Intake and consent

- Each treated person owns their own forms, charts, photos, and clearance results, including every member of a group booking and every child booked by a parent. The appointment links to the person's record; a payer or booking organizer does not become the clinical subject.
- A clinic creates reusable intake, history, treatment consent, and chart templates and chooses the services that require each. It can ask for a form once, each visit, or again after a set expiry. Forms may be completed before the visit or at check-in. A pending form does not cancel an appointment; staff can see what remains before treatment.
- The clinic supplies its own consent wording and clinician conversation. A recorded signature shows who agreed, in what capacity, to which version, and when. It does not itself certify treatment suitability. Keep treatment consent separate from optional permission to use before/after photos in publicity; refusal or withdrawal of publicity permission must not erase the clinical photo or change treatment consent.
- Submitted answers and signatures remain part of the person's history, including old versions and expired submissions. Staff may record that an outside or paper form was completed, naming the source and responsible staff member; that marker is not a digital signature. Corrections are attributed, dated additions, not silent edits to a signed response.

### Children and representative access

- Staff verify and record who may act for a child, including the scope and end of that authority. A parent or guardian answers and signs on the child's record, with their own identity and capacity recorded. Where law allows a child to consent to particular care independently, that treatment's record and access rules follow the applicable law; staff do not assume every parent link covers every record.
- A verified parent or guardian can see the child's legally accessible records, including treatment notes, through the authenticated portal. Staff can restrict specific records when applicable law or an individualized clinician safety decision requires it; the reason, decision maker, scope, and review are recorded. A staff-managed route handles legally required access that the portal cannot express. There is no blanket rule hiding all charts from parents.
- Minor-based access ends at the applicable adult age or earlier legal change. An adult may grant a separate, legally effective representative authority. The clinic needs state-specific legal guidance before using minor consent and access settings in a state; the product does not supply one universal legal age or consent rule.

### Clinical chart and treatment clearance

- Staff document each person's visit in a staff-only chart, with notes, treatment details, and clinical photos where needed. Photos keep their capture context and annotations. Copying previous text into a new draft is explicit; a prior image is never presented as newly captured. Submitted charts are locked and corrected with attributed, time-stamped additions.
- A required consultation, patch test, or good faith exam has an explicit clinician result: cleared, not cleared, or needs follow-up. Record the clinician, date, applicable treatments, validity or expiry, and linked visit or chart. The clinic chooses its service-specific validity and timing rules in line with its state and clinical policy. A completed visit alone is not clearance.
- If clearance is missing, expired, reversed, or not passed, an existing treatment booking remains on the calendar and is flagged for staff. A staff member's permission to book past a warning does not grant medical clearance. Treatment cannot be marked started until an authorized clinician records current clearance.

### Review and prescribing

- The clinic chooses which form or chart templates require a named supervisor's review. The record distinguishes draft, submitted and awaiting review, signed off by a named reviewer, and explicitly completed without review by an authorized person. A bulk action or an appointment's checkout is never presented as an individual review. Checkout may finish while review is pending; the queue keeps pending and overdue work visible.
- Intake can collect current medicines and allergies. A clinician must reconcile that information into any future prescribing system before relying on interaction or allergy checks; free-text answers alone are not such checks. Electronic prescription creation is planned only through a qualified provider integration with prescriber credentialing, required controlled-substance controls, and an outage path. P3 decides release timing; no native prescribing capability is promised by this planning part.

Clinical details and photos stay in protected records; appointment texts and emails do not expose them. Staff access, audit, deletion/export, notification, and integration details belong to P2D, P2E, and P2G. The final US launch behavior needs state-specific review of minor consent/access, consent text, clinical policy, and prescribing requirements.

## Commerce

Settled 2026-10-07 from the strongest documented Boulevard pattern, with Vagaro and Zenoti used only where
Boulevard is unclear or weaker. Evidence and limits: [P2C commerce research](research/boulevard-commerce-2026-10-07.md).
Release assignment remains P3's job.

### Checkout and financial history

- Appointment checkout records what actually happened: treated client, performed services, responsible staff,
  used products or units, retail items, discounts, tips, taxes and payment sources. Staff may correct the bill
  before completing it; every price or item change is attributed and remains visible in the order history.
- One order may use several payment sources. Card, cash, gift card, client credit, voucher, prepaid units and a
  recorded outside payment remain named separately. Recording an outside payment does not claim the platform
  processed or verified it. A processing or failed payment never counts as collected.
- The full total must be accounted for before checkout closes. An unfinished order stays open for staff to
  resolve. Completion records the appointment and purchase, updates applicable stock and value balances, and
  produces a receipt the client can view later. Email is available without marketing consent; text follows
  transactional-message consent.
- A closed order is not silently rewritten. A same-day full correction is a permissioned void with a reason and
  linked replacement. Later or partial corrections are refunds against named line items. The original, refund,
  restored value, stock decision and any commission reversal all remain visible.
- Group checkout may choose one payer, but each service stays attached to the person treated. Payer, treated
  client and owner of a voucher or prepaid balance remain separate roles.

### Deposits, cancellation fees and client credit

- A booking deposit is card money reserved for one appointment, not unrestricted store credit. The client and
  staff can see the appointment, amount and status. At checkout it applies automatically to that appointment.
- Rescheduling moves the deposit to the replacement appointment. If the business cancels, or the client cancels
  before the disclosed deadline, the deposit returns automatically to the original payment method. The client
  may deliberately choose account credit instead; the business cannot silently force that choice.
- A late-cancel or no-show fee follows the policy shown when booking and never exceeds the appointment value.
  The system calculates the fee and applies the linked deposit first, but staff confirm or waive it and record
  why. Only any remainder is charged; excess deposit is returned or credited according to the disclosed policy.
  Automatic charging may be planned later as a business opt-in, not assumed for the first release.
- Account credit is unrestricted client money, does not expire, and keeps an attributed history of purchases,
  refunds and permissioned adjustments. It remains distinct from deposits, gift cards, service vouchers and
  product units even though checkout can combine them.

### Memberships and packages

- A membership is a recurring agreement with a price, billing cadence, commitment or notice where used, and
  benefits such as member prices, service vouchers or account credit. A package is a one-time purchase of
  named benefits. Neither is a clinical treatment plan or proof the person is cleared for treatment.
- The client sees and accepts the exact version of price, cadence, commitment, cancellation notice, benefit
  end, expiry and refund terms before payment. Later catalog edits do not silently rewrite an existing
  purchase. A material change needs its own effective date and any consent the applicable rule requires.
- A successful term payment issues that term's benefits once. Retriable card failures receive bounded retries
  and clear client/staff alerts; a terminal failure is not repeatedly charged. During retry or past due, no
  duplicate or new benefits issue and active-member discounts stop.
- Payment trouble, pause or cancellation never erases value already paid for. Existing credit, vouchers and
  units follow the terms disclosed when issued. Billing end and benefit end are recorded separately. A client
  can stop future renewal through the portal without first paying arrears; the effective date and confirmation
  are clear and retained.
- Money-style account credit never expires. A service voucher or unit balance expires only when an expiry was
  clearly shown before purchase and is lawful for the state served. If no expiry was disclosed, it remains.
- A partly used membership or package is normally refundable only up to its unused paid value. Before approval,
  staff see the amount paid, value issued and used, remaining liability, benefits being removed and proposed
  refund. A permissioned manager may make a recorded goodwill exception. State law or the accepted agreement
  may require a more generous result.

### Vouchers, prepaid product units and sharing

- A service voucher pays for an eligible service; it is not a general discount. Refund of that service restores
  the voucher unless the refund deliberately resolves the original benefit purchase instead. The oldest valid
  eligible voucher is suggested first, with the source and expiry visible.
- Product units represent measured product used in treatment. Staff record the actual units used against the
  treated person's service. Refunding that redemption restores the exact reversed units. Refunding the unit
  purchase removes only unused units and returns their actual paid value; it can never create a negative unit
  balance.
- A membership, package or unit balance may be bought and used during the same visit. Payment succeeds first,
  then the benefit is issued, then it is redeemed. The staff sees one guided journey, while the history keeps
  the purchase and use as two linked events.
- A benefit is personal unless its purchase terms allow sharing. Another person may use it only through an
  existing owner authorization or explicit owner consent recorded by staff. Being in the same group checkout
  is never permission. History names the owner, recipient, appointment, source benefit and staff member.

### Gift cards, offers, discounts and tips

- Gift cards have their own balance and history and may pay part of an order. Sale, delivery, redemption,
  refund, permitted adjustment and deactivation stay traceable; they never merge into a client's account-credit
  balance. State-specific gift-card rules are checked before launch.
- A named offer is a reusable promotion with eligibility, timing, item and usage rules. A manual discount is a
  staff decision requiring a reason and appropriate permission. Each reduction stays attached to its line item.
  Offers stack only when their setup explicitly allows it; the system does not accidentally combine every
  matching promotion.
- Tips remain separate from service price and tax and are attributed to the intended staff member. A tip added
  after checkout becomes a linked tip-only purchase rather than rewriting the closed service order.

Before a US state launch, renewing-plan cancellation, paid-value expiry and gift-card terms receive
state-specific review. Payment-provider capability, saved cards, hardware, financing, tax calculation, release
scope and reuse of the contractor payment system remain for P3 feasibility and release assignment.

## Communications

Settled 2026-10-07 using Boulevard's documented operational pattern and Jafar's direction to use the
recommended safe rule where Boulevard or an established competitor does not answer a gap. Evidence, limits and
vendor differences: [P2D communications research](research/boulevard-communications-2026-10-07.md). P3 still
assigns release timing and checks whether existing Communications, Reviews and Automation work suits these
industries.

### Appointment notices and the staff inbox

- A booking sends a confirmation immediately to an available, permitted channel. By default, an unconfirmed
  appointment receives an email reminder two days before the visit. The business can choose a reminder time
  from a small set within one to five days. A same-day text reminder is optional; it can be enabled only when
  the business's texting is approved and the client permits appointment texts. When a channel is unavailable or
  delivery fails, staff see that outcome rather than a false delivered or confirmed state. A client without an
  email address can use a permitted text or the authenticated appointment page; lack of a sendable channel does
  not secretly cancel a booking.
- Confirmation changes an appointment only through its secure appointment action or an exact standalone reply
  to the current, uniquely identified text prompt. A reply containing other words, including “yes, cancel my
  appointment,” is a staff message, not confirmation. A text asking to cancel or move an appointment goes to
  staff; the secure appointment page follows the cancellation deadline and fee rules in Booking and identity.
  Confirmed, cancelled or moved appointments stop obsolete pending reminders.
- One business conversation history shows staff messages and replies to operational or promotional texts,
  including failed sends, the source of an automated message, an owner, unread state and last-response time.
  Automation does not silently close a client request. After-hours replies identify when a human can follow
  up and avoid repeated auto-replies. Clinical concerns or urgent wording go to trained staff; an automated
  response is not presented as medical advice.
- A new waitlist entry and a newly opened time that matches existing entries appear in the calendar/front-desk
  work queue. Staff see the eligible requests, choose one client, and contact or book them. This does not send
  competing clients a promise of the same slot. No separate staff email or push alert is the default; that
  channel can be reconsidered after observing the workflow. Automatic client offers remain a separate later
  release choice.

### Consent, privacy and marketing

- Booking never enrolls a client in promotions. Appointment, care and payment notices are kept distinct from
  promotional email and promotional text, with channel and purpose preferences, evidence of consent where
  required, and withdrawal history. Promotional choices are separate and optional; leaving them unchecked
  cannot block booking. An imported phone number or past purchase is not marketing consent. A text opt-out
  blocks the relevant sends until a valid re-opt-in; a saved audience or staff action cannot bypass it.
- A child remains the subject of their appointment and clinical record. Notices go only to verified contacts
  authorized for that communication. Changing or ending a guardian's authority updates notice routing before
  the next send. Confidential care follows its restricted contact route rather than a blanket parent copy.
  Ordinary email and text use neutral wording and a safe link; treatment, diagnosis, form answers, photos,
  medication and chart details remain behind authenticated access. State-specific minor confidentiality and
  healthcare communication rules must be reviewed before serving that state.
- Marketing audiences may use nonclinical service and purchase activity only where the relevant industry,
  permissions and channel consent allow it. Ordinary campaigns do not target a condition, chart answer,
  medication, treatment outcome or a child's care. Before a campaign sends, staff see the eligible count after
  opt-outs, exclusions and recent-contact limits; eligibility is checked again at send time. The send history
  records who launched it and who was eligible, sent to, skipped or failed. Replies return to a staffed route.
  One-time campaigns and preset rebooking campaigns are inventoried, but their initial-versus-later release
  assignment remains P3's decision.

### Feedback and AI boundaries

- When review requests are enabled, every completed-visit client gets the same neutral chance to leave a
  public review regardless of an internal score. All may also leave private feedback. A low score can alert
  authorized staff for recovery, but must not hide or bury the public link. Rewards cannot depend on a
  review's rating or wording. Public replies do not confirm patient status or reveal treatment details.
  Ratings and review-request release timing remains with P3.
- Any future AI receptionist or writing aid is separately enabled and reviewed for its provider, privacy and
  handoff behavior. It may answer basic business questions and provide a booking link; it does not diagnose,
  give treatment clearance, disclose charts, provide medical advice or claim to complete a clinical booking.
  An unresolved or urgent call becomes a human transfer or callback task with a reviewable summary. AI release
  timing remains with P3; Boulevard's beta does not establish that our providers meet these conditions.

## Operations

Agreed by Jafar 2026-10-07. Boulevard's documented operations are the primary reference; Zenoti and
Aesthetic Record supply the clinical lot-and-expiry pattern where Boulevard has a documented gap. Evidence
and limits: [P2E operations research](research/boulevard-operations-2026-10-07.md). Release timing and
existing-app suitability remain P3.

### Staff access and daily work

- Start with distinct owner/operator, front desk, treating clinician, clinical reviewer/medical director,
  and stock manager access templates. The person's actual permissions, not their title, decide access. A
  business owner or staff administrator does not automatically see clinical records. Separately control
  personal details, clinical-record reading, chart editing, clinical clearance, sign-off, bypassing review,
  stock adjustments, refunds, exports, and team access. No one can grant themselves broader access. Enforce
  these checks on pages, API actions, files, exports, and integrations.
- The booking requirement override is a named permission for an owner/operator or explicitly authorized
  front-desk manager; ordinary front-desk and treating-clinician templates do not receive it automatically.
  A reason and actor are recorded. It allows staff to book past a warning, never to supply medical clearance
  or override an age or legal restriction. Clinical clearance stays with an authorized clinician.
- When someone leaves, suspend their account and end active sessions immediately. Keep their future
  appointments visible with a reassignment owner and their past actions attributed to them. Staff see a
  daily unresolved-work list for unfinished visits and orders, pending charts and sign-off, clearance flags,
  timecards, stock variances, and recall holds. Each item has an owner and due date; closing the day does
  not silently dismiss it.

### Products and stock

- Keep retail items, ordinary professional supplies, and clinical products distinct. Receiving, sales,
  actual treatment use, returns, loss, damage, and counted corrections change stock through attributed
  movements. A refund changes money, but returning a physical item to usable stock is a separate decision.
  Partial deliveries and count differences remain visible for follow-up.
- A clinic can designate an injectable or other selected clinical product for lot and expiry tracking.
  Receiving records each lot, expiry, and quantity. Use records the exact lot and quantity against the
  treated person and visit; wastage and corrections are separate attributed movements. Expired or
  quarantined stock cannot be selected for treatment. A recall lookup identifies affected remaining stock
  and visits. Do not promise managed injectable stock in a release unless this complete trace is verified;
  until then the clinic keeps those products in its external stock record.
- Staff can propose a stock count difference. A stock manager reviews material loss or adjustments with a
  reason; returned clinical products stay quarantined until a qualified person documents that they may be
  used again. The clinic sets materiality, storage, and product-specific policies before use. Do not silently
  permit negative stock or erase an earlier movement.

### Clinical privacy and security

- Each staff member uses their own identity. Clinical and privileged staff use stronger sign-in verification
  and a short inactivity timeout; suspension revokes sessions. A record of clinical reads, edits, sign-off,
  exports, downloads, access changes, and emergency access shows who acted, when, which person's record was
  involved, and the reason where relevant. Authorized clinic leadership reviews exceptions. An audit entry
  does not imply the action was clinically approved.
- An authorized clinician may use a time-limited emergency access route when normal permissions would delay
  necessary care. They must state a reason; the access is recorded and sent for later review. Emergency
  record access does not create missing treatment clearance or override consent. Exact emergency policy
  needs clinic and state review before launch.
- A client deletion request becomes a reviewed privacy case. Restrict access while preserving medical,
  payment, and audit records for applicable obligations; offer access or amendment through the appropriate
  route. When disposal is permitted, record what was removed, when, and by whom. Do not set one US-wide
  retention period. The applicable states and provider contracts must be reviewed before clinical launch.

## Reporting and reconciliation

Agreed direction 2026-10-07 after checking official Boulevard guidance and Zenoti where needed. Evidence, version limits and proposed safeguards: [P2F reporting research](research/boulevard-reporting-2026-10-07.md). This sets behavior, not first-release assignment or a claim that the contractor reports already support it.

- A business summary separates **closed sales**, **new money received**, **previously paid value redeemed**, **care and products delivered**, and **processor payouts**. Each total names its date basis, currency, tax/tip treatment and included states. An open order, failed payment or unconfirmed outside payment does not appear as collected money. Using a gift card, credit, voucher or product unit never creates a second card receipt. Prepaid purchase and later fulfillment may each appear in their respective views, but they are not added together as one new-money or revenue total.
- Staff can follow a difference from the summary to its order, line item, payment, refund, benefit movement or payout. Refunds and voids retain the original and correction. Payment date, settlement date, payout date and bank-arrival confirmation stay distinct. Processor fees, disputes, holds, releases and adjustments explain why card receipts differ from a bank deposit. Cash-drawer counts reconcile physical cash only. Recorded outside payments remain visibly unverified by our processor.
- A client and permitted finance staff can see unused account credit, gift cards, service vouchers and prepaid product **unit quantities** separately, as of a chosen date, with dated issue, use, refund and correction history. Business reports show outstanding value for the money-based balances without offsetting it against a client's unpaid bill. Unit purchase value and redemption are traceable, but a monetary liability total for product units requires a verified valuation and accounting rule before it is promised.
- Stock reporting separates on-hand physical quantity, each attributed movement, and estimated stock value. It labels the cost method, valuation date and excluded products. A current estimated value is not presented as historical treatment cost or as proof of a physical count. Lot-tracked clinical use and wastage link back to the treated person and visit under the clinical permissions agreed in Operations.
- A selected pay period shows each staff member's permitted sales, tips, commission basis, refund clawback and approved corrections or reassignments. Earlier entries remain visible when a later correction changes the amount. The report is reviewed and exported for the clinic's payroll process; it does not claim wages, overtime, tax withholding or that staff have been paid.
- Effective permissions govern reports, underlying rows, downloads and saved views consistently. Finance access controls business money and payout details; clinicians may see only their own permitted performance; stock staff may see counts without automatically gaining cost, sale-price or clinical-record access. A download cannot expose fields hidden on screen. No financial or stock export includes protected clinical notes merely because it identifies an appointment or product.
- The daily unresolved-work view includes open orders, failed or pending payments, unexplained cash variance, payout exceptions and the operational exceptions already agreed. Each item has an owner and resolution history. A day may close with visible exceptions; closing does not mark missing money as received.

The existing contractor financial reconciliation rules and readers are reuse candidates only. P3 checks their suitability for appointments, prepaid value, stock, commission, payout data and reporting permissions before assigning release scope. Reports use the organization's timezone and one named currency; source dates and stable IDs permit accountant tracing. No capacity or accounting-software claim follows from this planning section.

## Connected journeys

Agreed by Jafar 2026-10-07 using Boulevard's published connection, migration, mobile and location behavior, with Zenoti as a focused comparison for old balances and cross-location redemption. Evidence and limits: [P2G connected-journey research](research/boulevard-connected-journeys-2026-10-07.md). P3 still chooses actual first-release integrations and mobile surfaces and checks provider and existing-app suitability.

- Website, social and other booking entry points use the same appointment, person identity, service eligibility, deposit and notification rules. The appointment in this platform is the booking record. A personal calendar may block time or show a neutral event, but its delayed or failed sync does not become a second booking authority. Staff can see and resolve connection failures.
- The business owner approves each external connection's purpose, permitted data and actions. The business sees its connection status and last success or failure. General business, marketing, calendar and accounting connections do not receive clinical charts, forms, photos, treatment details or confidential minor records. Disconnecting stops future sharing; staff are told that copies already held by another provider may need separate removal. Booking, clinical, financial, export and audit permissions apply on every connected surface.
- Moving from old software starts with a source-specific sample and a review of person matches, unmatched/conflicting records, future appointments, history and prepaid balances. Authorized staff approve mappings and totals before imported data is used. Keep the source and import date visible; unresolved records stay in a review queue. An imported phone number or opt-in flag alone never grants marketing permission. Imported clinical files are historical material until a qualified clinician reviews what is relevant to current care. Import does not create treatment clearance, chart sign-off or a current prescription. The clinic is told which source data can be moved automatically and which needs individual handling; no full clinical-history migration is promised without source-specific proof.
- A mobile or customer-facing surface follows the same identity, clinical privacy, staff access and money rules as the main workspace. If it does not support an action, it directs the user to a supported surface rather than appearing to complete it. Native staff apps, customer kiosks and card-present hardware have separate release and provider checks in P3.
- The first release serves one location. In a later multi-location experience, a person may keep one business-level identity while appointments, staff access, prices, stock, payments and prepaid benefits retain their location. Cross-location use of a membership, package, gift card or other prepaid value needs an explicit clinic rule and a traceable purchase/use/settlement history before it is enabled. Shared identity never grants unrestricted clinical access at another location.

P3 must check complete journeys across these boundaries: outside booking through clearance and checkout; migration of a duplicate client with old chart, balance and opt-out; a failed stock or accounting sync after a sale; and a later visit at another location. A connection failure must not quietly create a booking, balance, payment, stock or permission claim that the platform cannot support.

## Still unclear

- Detailed behaviors, unresolved evidence gaps, reuse findings, release assignments, and measurable quality targets; settle these in planning parts, not by assumption.
- Performance: representative workloads and per-route/browser budgets for the agreed initial release. P3A
  must settle these before build parts are approved; implemented slices must then supply the stated evidence.
- How client sign-in is built alongside the existing staff sign-in, and how saved cards fit the current Stripe key (P3).
- Clinical records: which agreed capabilities belong in the initial release, what can be reused, and which qualified prescribing provider could support an integration (P3). State-specific minor access and clinical-policy review must be completed for the states served before launch.
- Reporting: the accounting method for valuing unused prepaid product units, provider payout-data availability, and initial report selection need P3 verification before a monetary liability, automatic bank match or release promise.
- Connections and migration: which specific integrations, mobile surfaces and source-vendor imports pass P3 feasibility and belong in the initial release. The attached Boulevard historical-file PDF's import format remains unverified; do not promise automatic clinical-history migration from it.
- Whether Beauty & Spa lets under-age clients book online on their own; settle this when that edition is planned.

## Not doing

- Application or infrastructure implementation during this planning campaign; build parts follow approval.
- Treating undocumented vendor behavior, market leadership, or private architecture as verified facts.
- Assuming support for every medical specialty from the term clinical wellness.
- Replacing or relaxing existing contractor behavior through this expansion plan.

## Research

- [Completed P1 public-source inventory and coverage limits](research/boulevard-feature-landscape-2026-10-05.md).
- [P2A booking and identity evidence and original drafts](research/boulevard-booking-identity-2026-10-05.md); agreed behavior is in [Booking and identity](#booking-and-identity).
- [P2B clinical-record sources and evidence limits](research/boulevard-clinical-records-2026-10-06.md); agreed behavior is in [Clinical records](#clinical-records).
- [P2C commerce sources, vendor gaps and selected mature patterns](research/boulevard-commerce-2026-10-07.md); agreed behavior is in [Commerce](#commerce).
- [P2D communications sources, vendor gaps and selected safeguards](research/boulevard-communications-2026-10-07.md); agreed behavior is in [Communications](#communications), while marketing, reviews and AI release timing belongs to P3.
- [P2E operations sources and clinical stock gap](research/boulevard-operations-2026-10-07.md); agreed behavior is in [Operations](#operations), while release timing and existing-app reuse belong to P3.
- [P2F reporting measures, reconciliation, permissions and source limits](research/boulevard-reporting-2026-10-07.md); agreed direction is in [Reporting and reconciliation](#reporting-and-reconciliation), while release timing and existing-app reuse belong to P3.
- [P2G connected-journey evidence, approved safeguards and migration limits](research/boulevard-connected-journeys-2026-10-07.md); agreed behavior is in [Connected journeys](#connected-journeys), while release timing and feasibility belong to P3.
- [Industry entry and onboarding patterns](research/industry-onboarding-entry-patterns-2026-10-07.md); agreed direction is in [Business entry and onboarding](#business-entry-and-onboarding).

Primary public entry points:

- [Boulevard feature catalog](https://www.joinblvd.com/)
- [Boulevard support center](https://support.boulevard.io/)
- [Boulevard Academy](https://www.academy.joinblvd.com/)
- [Boulevard release notes](https://changelog.joinblvd.com/)
- [Boulevard developer portal](https://developers.joinblvd.com/)

# Boulevard-inspired industry editions

**Status:** Planning — overall direction and booking/identity behavior agreed 2026-10-05; clinical-record behavior agreed 2026-10-06; other areas and release scope remain in planning.

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

## Still unclear

- Detailed behaviors, unresolved evidence gaps, reuse findings, release assignments, and measurable quality targets; settle these in planning parts, not by assumption.
- Booking and identity items owned by later parts:
  - Charging late-cancel and no-show fees automatically or by staff decision, and refunding deposits (P2C).
  - Reminders and text-reply confirmations, and where waitlist alerts appear (P2D).
  - Who holds the requirement-override permission, and client data deletion (P2E).
  - How client sign-in is built alongside the existing staff sign-in, and how saved cards fit the current Stripe key (P3).
- Clinical records: which agreed capabilities belong in the initial release, what can be reused, and which qualified prescribing provider could support an integration (P3). State-specific minor access and clinical-policy review must be completed for the states served before launch.
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

Primary public entry points:

- [Boulevard feature catalog](https://www.joinblvd.com/)
- [Boulevard support center](https://support.boulevard.io/)
- [Boulevard Academy](https://www.academy.joinblvd.com/)
- [Boulevard release notes](https://changelog.joinblvd.com/)
- [Boulevard developer portal](https://developers.joinblvd.com/)

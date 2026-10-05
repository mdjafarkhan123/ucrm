# Boulevard-inspired industry editions

**Status:** Planning — overall direction agreed 2026-10-05; public-source inventory completed 2026-10-05; booking and identity behavior agreed 2026-10-05; other areas and release scope remain in planning.

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

The [public-source inventory](research/boulevard-feature-landscape-2026-10-05.md) records stable identifiers, purposes, sources and availability boundaries. P2 will add detailed workflows, settings, permissions, exceptions and dependencies. P3 will record existing-app suitability, release assignments and completion checks. Detailed area plans will be linked here as they are researched.

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
- On the child's adult birthday, every parent link ends automatically. Future appointments stay booked, and
  staff get an alert to add the client's own phone or email so they can sign in. *MyChart proxy ends at 18.*
- What a parent may see of a child's forms and treatment records, and parent consent forms, belong to the
  clinical records part (P2B). *Jane shows shared chart entries only in the patient's own login.*

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

## Still unclear

- Detailed behaviors, unresolved evidence gaps, reuse findings, release assignments, and measurable quality targets; settle these in planning parts, not by assumption.
- Booking and identity items owned by later parts:
  - Charging late-cancel and no-show fees automatically or by staff decision, and refunding deposits (P2C).
  - Reminders and text-reply confirmations, and where waitlist alerts appear (P2D).
  - Parent consent forms, parent access to child records, and recording a passed requirement (P2B).
  - Who holds the requirement-override permission, and client data deletion (P2E).
  - How client sign-in is built alongside the existing staff sign-in, and how saved cards fit the current Stripe key (P3).
- Whether Beauty & Spa lets under-age clients book online on their own; settle this when that edition is planned.

## Not doing

- Application or infrastructure implementation during this planning campaign; build parts follow approval.
- Treating undocumented vendor behavior, market leadership, or private architecture as verified facts.
- Assuming support for every medical specialty from the term clinical wellness.
- Replacing or relaxing existing contractor behavior through this expansion plan.

## Research

- [Completed P1 public-source inventory and coverage limits](research/boulevard-feature-landscape-2026-10-05.md).
- [P2A booking and identity evidence and original drafts](research/boulevard-booking-identity-2026-10-05.md); agreed behavior is in [Booking and identity](#booking-and-identity).

Primary public entry points:

- [Boulevard feature catalog](https://www.joinblvd.com/)
- [Boulevard support center](https://support.boulevard.io/)
- [Boulevard Academy](https://www.academy.joinblvd.com/)
- [Boulevard release notes](https://changelog.joinblvd.com/)
- [Boulevard developer portal](https://developers.joinblvd.com/)

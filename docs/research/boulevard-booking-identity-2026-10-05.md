# Boulevard booking and identity research (P2A)

**Accessed:** 2026-10-05. **Status:** P2A in progress — research complete; proposals and owner decisions are
drafts and not approved. Part of [Boulevard-inspired industry editions](../boulevard-product-behavior-contract.md).

## Summary

Boulevard now signs clients in with a one-time code by text or email, and medspas add a date-of-birth check
before anything private is shown (GAP-04 resolved). Boulevard documents no family or guardian accounts, no
per-service age limits, and no rule that a consultation, good faith exam or patch test must come first; it
relies on staff alerts, blocked clients and expiring forms. Competitors fill those gaps: Jane and Vagaro link
family members with permissions, Zenoti enforces prerequisite visits with validity periods, Phorest and
Fresha track patch tests, and Aesthetic Record flags appointments without a valid good faith exam. Boulevard's
service, availability and appointment rules are well documented and are the proposed baseline.

Working notes and the downloaded source pages live in `.scratch/boulevard-p2a/` (local only, not in Git).

## Evidence — client sign-in, identity, profiles, family/minors

Local copies: all 465 Boulevard help articles as text in `.scratch/boulevard-p2a/identity-raw/alltxt/`
and 261 Boulevard release notes in `.scratch/boulevard-p2a/services-availability-raw/changelog.jsonl`
(fetched 2026-10-05). Later P2 parts can search these before fetching again.

### GAP-04 sign-in — RESOLVED (Confirmed)
- Changelog 2025-10-14 "Quicker, more secure self-booking login with one-time codes sent via email or text":
  clients log in to self-booking with a one-time code to phone or email; texted codes autofill on mobile
  (https://changelog.joinblvd.com/quicker-more-secure-self-booking-login-with-one-time-codes-sent-via-email-or-text-325129).
- Changelog 2023-11-07: portal sign-in code could already go by email; text option added
  (https://changelog.joinblvd.com/text-clients-their-verification-code-278613).
- Client Portal article (updated 2026-09-28) https://support.boulevard.io/en/articles/8648439-client-portal :
  - code by email or text ("Rolling out now").
  - HIPAA-covered businesses (HIPAA add-on, Medspa add-on, Aesthetics bundles): after the code, client must
    confirm date of birth before seeing any appointment, form or profile detail. Exact match against file;
    none on file → entered once, saved, not overwritten by later logins; mismatch → can retry.
  - Shared profiles setting: when several profiles share an email/phone, business may let client choose
    profile at login. HIPAA businesses advised OFF → client told to contact business so duplicates are merged.
    Changelog 2023-12-14: setting shipped OFF for medspas, IV clinics, medical offices.
  - Client can update name, birthday, pronouns, address, communication preferences in portal; CANNOT change
    email or phone (they are the login identifiers).
  - Portal reached via "Manage appointment" link in confirmation, "Your appointments" in booking overlay, or
    portal URL. New client without account is told to "Book Now".
  - Gift cards not visible in portal.
- Online Booking Account article (updated 2026-06-05) https://support.boulevard.io/en/articles/6950782-online-booking-account
  still describes email + password created at end of booking, and "Forgot Password" recovery code → LEGACY.
  Same article: account is linked to profile BY EMAIL; booking with a different email creates a second
  profile → staff merge. Cross-business: an online booking account (and its card) works across ALL Boulevard
  businesses ("card travels") — a network-level consumer identity.
- Developer doc (Client API auth 2026-06) is API tokens only; no client session-length fact. Session length for
  CLIENTS not documented. Staff: auto logout nightly (Dashboard) / weekly (app), changelog 2026-08-17.

### Duplicates and merge (Confirmed)
- Changelog 2026-03-17 + Client Profiles (2026-09-29): when STAFF create a client matching first+last name,
  email, or phone of an existing client → warning, option to pick existing (choose among several matches).
  Creating a client without phone → prompted to add one.
  https://changelog.joinblvd.com/reduce-duplicate-clients-and-capture-more-phone-numbers-with-new-staff-warnings-334003
- Online self-booking links by email only (above) → duplicates still arise online.
- Merge (updated 2026-10-01) https://support.boulevard.io/en/articles/5941428-merging-client-profiles :
  cannot be undone; pick which value to keep per field; consolidates notes, orders, appointments, cards,
  accommodations, images, forms; needs "view clients contact info" + "merge client profiles" permissions;
  find duplicates via Client Records Report. Related article: ePrescribe migration (prescriptions caveat).
- Client profiles cannot be deleted (tied to reporting); to stop contact remove phone+email.

### Profile data (Confirmed)
- Client Profiles: name, phone, email, pronouns (if enabled), referral source, referral link, marketing
  opt-ins, tags, birthdate + age (if enabled), home address (US/international). Overview metrics:
  appointments, show rate, average revisit, average revisit value. Tabs: Accommodations, Messages, History,
  Wallet, Memberships, Packages, Products, Forms & Charts, Gallery, Files, Loyalty.
- Changelog 2025-09-05: "Display client age" setting (location) shows age on appointment window + profile.
- Changelog 2026-03-03: "Sex Assigned at Birth" profile field; access via "Client Clinical Details"
  permission; can be a connected form field; Aesthetics/Enterprise plans.
- Changelog 2021-06-28: pronouns optional (location setting, default off); client can set at online booking.
- Profile change alerts: automated message to client when email or date of birth changes (Client Profiles).
- Scheduling Alert (updated 2025-11-04) https://support.boulevard.io/en/articles/5941470-scheduling-alerts :
  one active alert per client, staff-only, red banner in New Appointment window + appointment preview. Warning
  only — not a block.
- Block client (updated 2025-11-04) https://support.boulevard.io/en/articles/5941418-blocking-a-client :
  Business/Location Manager permission; reason + attachments saved as client note; blocked client signed in
  sees no times and cannot join waitlist; email/phone match at booking → error; staff "View Times" also blocked
  but staff can still place on calendar manually; filter list of blocked clients.
- Accommodations (updated 2025-11-04): custom price/duration per client per service (optionally per provider),
  applies automatically to future online and staff bookings; set only by staff on web.

### Family, minors, booking for others
- Boulevard: NOT FOUND in public docs — no family/dependent/guardian profiles, no per-service minimum age, no
  booking-for-someone-else flow except group booking guests. Shared memberships exist (benefits sharing, not
  identity). Only age DISPLAY exists. Grep of all 465 articles for minor/guardian/dependent/family/under 18:
  no relevant hits.
- Competitor-derived — Jane App (clinical scheduling; official guides, fetched 2026-10-05; URLs to verify):
  - "Relationships" link two profiles with granular permissions: View and Pay; Book appointments + waitlist
    (also sees their appointment history); Fill out intake forms on their behalf (can't see forms the person
    filled themselves); receive copies of booking emails/reminders; receive billing emails/SMS; calendar
    subscription. Patient gets an email whenever their info becomes shared through a relationship.
  - Online: new patient says whether account is for themselves or someone else; relationship, first and last
    name required; "Will you be paying on this person's behalf?". "Family Members" tab in My Account to add
    people and edit the permissions THEY grant.
  - Booking for family: choose who the appointment is for (dropdown); multiple family members in one session;
    appointment lives on the family member's profile; card checked on the BOOKER's profile; appointment limits
    count against the booker.
  - "Contact" (non-patient guardian/payer) linked to a patient, no clinical record; becomes a patient if they
    book.
  - Chart entries shared with a patient visible only in that patient's own login, never through family.
  - Child/teen with own email: financial messages can be routed to the parent only.
  - Jane: "not possible to limit new clients from booking only certain appointment types"; can restrict whole
    online booking to approved/existing clients (Only Allow Approved Online Booking).
- Vagaro family pages blocked by Cloudflare in fetch — not read.
- Established health-portal pattern for minors (search 2026-10-05): parent/guardian proxy access to a child's
  portal ends automatically at 18; the adult may grant access again; teens 13–17 often get limited proxy
  views. Examples: https://www.mylrh.org/mychart-pediatrics/ , https://www.tfhd.com/mychart-proxy-access/ ,
  https://legacy.bjc.org/Portals/0/MyChart/Documents/MyChart-Proxy-Adolescent-12-17.pdf (hospital MyChart
  pages; pattern evidence, not a medspa rule).
- Per-service minimum age: no vendor help article found in a quick search (2026-10-05) — OPEN; Boulevard only
  displays age.

## Evidence — may this client book this treatment?

### Boulevard (what exists)
- NOT FOUND in 465 public articles: prerequisite-service rule, consultation-required rule, good-faith-exam
  tracking, patch-test records, new-client-only / returning-only services, per-service minimum age,
  booking approval/request flow.
- Tools Boulevard does document:
  - Service "Bookable online" on/off and staff "Bookable online" vs "Assignable" (internal only)
    https://support.boulevard.io/en/articles/5941347-enabling-and-disabling-online-booking (2025-07-18).
    Disabled service still bookable by staff.
  - Deep links to an item/category only work if the item is bookable online (no hidden-but-linkable
    service) https://support.boulevard.io/en/articles/5941527-self-booking-link-to-specific-items-or-categories (2025-01-09).
  - Restrict times via shifts, time blocks and lead-time rules; staff can always place appointments anywhere
    https://support.boulevard.io/en/articles/5941449-restricting-appointment-availability (2025-07-18).
  - Scheduling Alert (staff warning), Block client (online + "View Times").
  - Forms triggered by service; once-only vs every appointment; once-only forms can EXPIRE after months/years
    → client re-asked at first appointment after expiry; sent with confirmation / reminder / at check-in;
    not a booking block. https://support.boulevard.io/en/articles/6989798-forms-and-charts-building-forms-and-charts (2026-09-29)
  - Display client age (2025-09-05 changelog) — display only.

### Competitor-derived patterns
- Zenoti — prerequisite services (the most complete documented model):
  - Attach prerequisite services (consultation, patch test) to a main service, with order when several.
  - "Enforce prerequisites": guest cannot book the main service without booking the prerequisite.
  - "Allow prerequisites to be booked with the service": same visit vs separate earlier visit.
  - "Service validity": after a period the guest must redo the prerequisite (e.g. Botox consult ~6–7 months).
  - Prerequisite equivalents + validity days: e.g. hair colour in last 60 days → no new patch test.
  - Online: "when booking or rebooking, prerequisite conditions are checked… Tattoo Removal Consultation
    must have been completed within 180 days; otherwise, the guest will be prompted to book or complete it
    first". Front desk is alerted.
  - Sources: https://help.zenoti.com/en/consumer-experience/webstore/admin-tasks-for-booking-appointments.html ,
    https://help.zenoti.com/en/master-data/services/create-services.html ,
    https://help.zenoti.com/en/consumer-experience/webstore/guest-tasks-for-booking-appointments-in-webstore.html (fetched 2026-10-05; no page date)
- Aesthetic Record (medspa EMR) — GFE status (updated 2026-09-30)
  https://learn.aestheticrecord.com/en/articles/14891707-understanding-and-managing-gfe-status-indicators :
  per-service "requires a GFE?" toggle (in-person and virtual); colour icon on appointment cards/calendar:
  black = current valid GFE, green = covered by a still-valid GFE, red = no valid GFE (new one required);
  any procedure can be "Marked as GFE"; expiry configurable (e.g. 365 days) or none; Qualiphy (third-party
  telehealth GFE) approved exams auto-marked. It is a VISIBLE WARNING, not a booking block.
- Phorest (salon) — patch tests:
  - Service flag "Patch Test: Yes"; patch test record on client card (description, staff, status
    Pending/Passed/Failed).
  - Online: no Passed test AND appointment inside the "patch test period" (default 24h) → client CANNOT
    book; outside the period → told to visit for a patch test first.
  - "Will still allow you to check a client in and pay… even if you have recorded a failure… It is the
    responsibility of the business to ensure client safety."
  - https://support.phorest.com/hc/en-us/articles/360017402360 (2024-09-19),
    https://support.phorest.com/hc/en-us/articles/360016360879 (2024-06-17),
    https://support.phorest.com/hc/en-us/articles/360016362079 (2023-11-15)
- Fresha — patch tests https://www.fresha.com/help-center/knowledge-base/clients/55-record-client-patch-tests :
  per-service requirement; online client asked to confirm a valid patch test, else told to do one in-store;
  bookings NOT blocked; staff alert on manual booking; result Pending/Passed/Failed; valid six months fixed;
  reminders in notifications; expired tests kept in history.
- Jane — new vs returning: "doesn't have a single toggle to block new patients from booking online"; options:
  banner, rename treatment, per-treatment "Contact to Book", remove practitioner from online booking; or whole
  site "approved clients only". https://jane.app/guide/how-to-restrict-online-booking-to-returning-patients ,
  https://jane.app/guide/only-allow-approved-online-booking
- Mangomint — service category "Only show in online booking with direct link"
  https://www.mangomint.com/learn/add-categories-and-services/

### US context (not legal advice)
- AmSpa: a good faith exam is a medical evaluation before a patient's first treatment; establishes the
  provider–patient relationship and candidacy; states vary on telehealth, timing and who may perform it
  (MD/DO; NP/PA depending on state). https://americanmedspa.org/blog/what-is-required-of-a-medical-spas-good-faith-exams

### Pattern summary
- Hard block online + staff override is the common pattern where it exists (Zenoti enforce, Phorest period).
- Staff side is always warn-and-allow (Phorest, Aesthetic Record, Fresha, Boulevard alerts).
- Validity windows are per rule (Zenoti validity days, AR expiry setting, Fresha fixed 6 months, Boulevard
  form expiry).

## Evidence — services, availability, appointment lifecycle

All Boulevard support URLs are https://support.boulevard.io/en/articles/<id>; dates are "updated".

### Services
- Categories shown first online; every service in one category; services already on appointments can't be
  deleted (5941383, 2026-07-07). Separate "online service menu" order vs "scheduling order".
- Four time blocks per service (5941395, 2023-07-13): Duration (provider busy), Processing (client busy,
  provider free — bookable by others unless "Double Booking" off per service), Finishing (provider busy),
  Transition/cleanup (provider busy). Location can disable processing/finishing/transition.
- Modifiers: options with price/time, "# required to book" groups; not separate services (5941408, 2024-12-30).
- Add-ons: real services offered after a compatible base service; SAME provider must do base + add-on;
  "Add-on only" (can't book alone) and 0-minute add-ons; online the provider list is filtered to people who
  can do both; don't mix modifiers and add-ons on one service (6584601, 2026-03-06).
- Overrides: service default → role/person custom price, duration, processing, finishing, transition,
  online bookability, commission; custom tax per service. Changes apply only to appointments booked AFTER
  the change; existing appointments keep their price/duration (5941407 2026-07-07; launch FAQ 5941316).
- Client accommodations: personal price/duration per service (all staff or one provider), auto-applied
  online and by staff (5941448).
- Scheduling order numbers (decimals allowed) force service order in multi-service bookings; unnumbered =
  flexible (8923519, 2026-07-07).

### Who and when
- Online booking needs: service enabled at location, assigned to staff who can perform it, staff schedule
  published. Staff "Bookable online" vs "Assignable" (internal only). Provider list ordered by price high→low
  then alphabetical, not rearrangeable (5941347, 2025-07-18).
- Shifts: online booking only inside published shifts; staff can place appointments anywhere (5941438,
  5941449). Recurring weekly shifts, one-off shifts, "Publish as Unavailable" with reason (closures).
- Time blocks: reason hidden from clients; Personal vs Business (utilization); repeat up to 1 year; multi-
  staff blocks; permissions "Create own/all appointments" (5941379, 2026-10-01).
- Location hours are display-only for clients; don't affect scheduling (7898267).
- Lead time: "Up to" minimum notice and "Not more than" max horizon, business-wide (5941362).
- Rooms/equipment (5941355, 2026-09-22): categories; service needs exactly ONE resource from EACH assigned
  category; held for whole service incl. processing + transition; resources need their own schedule or
  online times disappear/double-book; clients never see resources.
- Precision Scheduling (6110033, 2025-07-18; 11776503, 2026-01-12): offers times that avoid small unusable
  gaps, based on most common services in a sliding 90-day window; waits between provider/resource changes
  capped at 15 min; filler-time interval 15–240 min; "First available" assignment = Prioritize Efficiency /
  Equal Opportunity / Less Busy Providers; group timing rules (same time / back-to-back / same start) —
  some settings only via Boulevard support. Staff see "Best Times" vs "All Times".
- Online checkout holds the chosen time 30 minutes; times computed live; if staff books over it, client is
  sent back to pick a new time (developer guide "Querying available dates and times").

### Appointment journey
- Online flow (5941525, 2025-09-22): category → service(s) → email or phone → code if known account → date
  and time (Precision) → waitlist if nothing fits → contact + card → deposit if required → book. A valid card
  is required for EVERY online booking; gift cards can't be used. Switch provider at review (single service).
  Optional up-front tip. "Communications" notice: booking = agreeing to reminder AND marketing messages unless
  a preference already exists (also changelog 2023-07-27).
- Staff booking (5941381): from calendar or client profile (rebook); no card required; Best/All Times or
  place on calendar. Same-day second appointment → prompt to merge (5941404).
- Requested provider heart; "First available" = not requested (5941413).
- Recurring: staff-only; set at creation; max 52; conflicts NOT flagged; cancel one or all future (5941424).
- Prebook from checkout with 4/6/8-week jumps; prebook % metric (5941405).
- Reschedule (6950738): drag, select-and-place, or edit; history records who/when; multi-service stays same
  day. Client self-reschedule only with the ORIGINAL provider, only outside the cancellation deadline,
  otherwise "call us"; location setting can turn client rescheduling off (changelog 2023-03-14).
- Cancel (5941385): reasons Mistake, Staff canceled, Client canceled, Client late canceled, No-show; fee only
  for late cancel / no-show and never automatic — staff tick "charge"; restore from Cancelled list
  (5941422). Text-reply keyword matching treats "yes… cancel" as confirmation (documented quirk).
- Policy (5941349, 2025-11-14): default up to 100% if cancelled <24h; custom % or $; fee capped at appointment
  value; deadline in hours; custom policy URL. Booking emails show "Free cancellation before <date time tz>".
- Deposits (5941467, 2026-04-09): % per service or per provider for online booking; stored as account
  credit; card only; members still pay; NOT auto-refunded on cancel; kept as credit on reschedule.
- Client confirmation only within first-reminder window (changelog 2023-03-20).
- Statuses/icons (5941417, 2026-09-11): confirmed, arrived, paid/finalized, new client, requested, client
  message, internal memo, forms not started, member; cancelled with/without fee. Front desk columns; optional
  "Active" state; moving to Completed opens checkout (5941360).
- Waitlist (5941433, 2023-07-13): location setting; client picks service+provider, card required, not charged;
  staff add with note; Edit/Book/Remove; online entries ignore closures and requested provider ("first
  available"); dashboard alert on new entry; no automatic offering.
- Group (7922463, 2025-07-22): online only (not dashboard); shared start time (dev guide); guest details
  optional → no profile/duplicates; forms go to booker; group can't be rescheduled by client.
- Staff leaving (5941450, 2026-10-04): future appointments never auto-cancelled; Suspend keeps them visible
  for reassignment; Deactivate HIDES them (not cancelled).

### Competitor-derived (where Boulevard is thin)
- Vagaro Online Appointment Rules (updated 2026-09-15)
  https://support.vagaro.com/hc/en-us/articles/204347060-Configure-Your-Online-Appointment-Rules :
  "Require Acceptance" (approval) per employee and customer type incl. N no-shows/cancellations; "Block New
  Customers" per employee; "Membership or Package Required to Book" per service; "Allow Family and Friends
  Booking"; waitlist modes You Pick / Money Maker / First in Line / Instant Book (offer with accept timeout);
  client cancel/reschedule cut-offs in hours; auto-refund prepaid on cancel option; lead time; max horizon up
  to 3 years; cleanup once at end vs after each service.
- Vagaro Family & Friends (2026-07-01)
  https://support.vagaro.com/hc/en-us/articles/1260804129909-Manage-a-Customer-s-Family-Friends :
  relationship Parent/Spouse/Sibling/Friend/Child/Pet; toggles: book for, view appointments, share card, CC
  notifications; adults must accept an emailed/texted invitation; child added with birthdate; email needed to
  share appointments of someone over 18; share memberships/packages.

## Proposed behavior — draft, not approved

These proposals follow the reference rule: Boulevard first; a competitor pattern only where Boulevard is
silent or weaker, and labelled. Nothing here is approved until Jafar answers the open decisions and approves
the plan. Settled answers move into the plan; this file keeps the evidence.

### Sign-in and identity (GAP-04 resolved)

- Clients sign in with a one-time code sent by text or email; no passwords. **Boulevard (current).**
- Medspa edition: after the code, the client confirms their date of birth before seeing any appointment,
  form or profile detail; first-time clients enter it once. **Boulevard HIPAA step.** Beauty & Spa: code only.
- Each business has its own client list and logins. **Deviation:** Boulevard lets one booking account and its
  saved card work across every Boulevard business; we do not, because each business's client records must
  stay private to that business.
- When one phone or email belongs to several client profiles, the medspa edition does not let the person pick
  a profile; it asks them to contact the business so each person gets their own contact details.
  **Boulevard medspa default.** Children are handled by the family decision below.
- Clients can update name, pronouns, address and message preferences in their portal, but not the phone or
  email they sign in with. **Boulevard.** A date-of-birth change sends the client an alert. **Boulevard.**
- Staff creating a client see a duplicate warning when name, email or phone matches, and must add a phone.
  Merging two profiles is permanent, keeps the values staff choose, and needs its own permission. **Boulevard.**
- Profiles with history cannot be deleted; deletion requests belong to P2E. Staff can block a client from
  online booking with a reason, and keep one staff-only booking alert per client. **Boulevard.**

### May this client book this treatment? (GAP-12, booking side)

- A service can list requirements: an earlier visit that must be completed first (consultation, good faith
  exam, patch test or laser test spot), how long that visit stays valid, the minimum gap before the treatment
  (for example 24–48 hours for a patch test), whether both may be booked in the same visit, and a minimum age.
  **Competitor-derived:** Zenoti prerequisites (enforce, book-together, validity, equivalents) and Phorest
  patch-test periods; minimum age has no vendor pattern found yet (open).
- A requirement counts as met only when the earlier visit is completed and, where the business requires it,
  marked passed or cleared; how that outcome is recorded is P2B's question.
- The calendar shows each appointment's requirement status. **Aesthetic Record GFE indicator.** Strictness
  online and for staff is decision Q2.

### Services, staff, rooms and open times

- Adopt Boulevard's model: four time segments (treatment, processing, finishing, cleanup); modifiers versus
  add-ons done by the same provider; staff and role price/time overrides; a client's personal price/duration;
  forced service order; rooms and equipment where a service needs one item from each assigned category for
  the whole visit; published shifts and time blocks; earliest and latest online booking times; existing
  appointments keep the price and length they were booked with.
- Online times avoid leaving awkward small gaps, with a setting to show every time; staff can always see
  every time. **Mangomint "avoid gaps" style now; Boulevard's advanced optimisation is a later option.**
- **Improvements over Boulevard:** staff get a clear warning before booking outside a shift, over a block or
  over another appointment; repeating appointments show clashes before saving; a provider with future
  appointments cannot be deactivated until each one is moved or cancelled (Boulevard hides them).

### The appointment journey

- Adopt Boulevard's online flow: services → sign-in code → time (held for 30 minutes while booking) → card →
  deposit if required → booked. Requiring a card is a business setting, on by default (Boulevard always
  requires one; Mangomint and Vagaro make it optional).
- Deposits per service or provider; cancellation deadline in hours; late-cancel and no-show fee as % or
  amount, never more than the appointment. Clients change or cancel themselves until the deadline, then
  are asked to contact the business; client rescheduling keeps the same provider and can be switched off.
  **Boulevard.**
- Statuses: booked, confirmed, arrived, in treatment (optional), completed; cancellations record a reason
  (mistake, staff, client, late cancel, no-show) and can be restored. Prebooking from checkout; repeating
  appointments staff-only. **Boulevard.**
- **Deviations:** booking never silently signs the client up for marketing (P2D settles consent); every guest
  in a group booking needs their own name and contact before forms or records are created (GAP-03).
- Left to later parts: automatic vs staff-decided fee charging and deposit refunds (P2C); reminder and
  text-reply confirmation rules (P2D); guardian consent forms (P2B); data deletion (P2E).

## Decisions for Jafar — round 1 (draft wording, not yet asked)

**Q1 — Teens and families.** A 16-year-old wants laser hair removal and her mum books it.
- A (recommended): parents can add their under-18 children and book, pay and receive messages for them; each
  child keeps their own record; the parent's access ends automatically at 18. Hospital patient portals
  (MyChart proxy access) and Vagaro's child profiles follow this pattern.
- B: full family and friends linking for adults too, with permission switches. Jane, Vagaro.
- C: none; each person books for themselves and staff book for minors. Boulevard.

**Q2 — Safety checks.** A new client tries to book Botox online without a consultation or exam.
- A (recommended): online booking stops and offers the required visit first; staff see a warning and can
  override with a written reason that is recorded. Zenoti, Phorest.
- B: reminder only; booking always goes through; staff see a red flag. Fresha, Aesthetic Record.
- C: no rule; staff rely on notes and alerts. Boulevard.

**Q3 — Waitlist.** A Friday 2 pm cancellation opens a slot that two waitlisted clients wanted.
- A (recommended for the first release): staff are alerted to matching waitlist clients and book one
  themselves. Boulevard plus an alert.
- B: the system offers the slot to clients automatically (first in line, accept within a set time). Vagaro.

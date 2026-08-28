# Contractor Settings Blueprint

**Status:** Approved by Jafar on 2026-08-21; Part 1 contract refined and confirmed on 2026-08-22  
**Purpose:** Explain, in everyday language, what contractors can find in Settings, what each area controls, and when each part should be built.

This document describes the contractor-facing Settings area. It does not cover Jafar's separate Platform Owner controls.

## The simple idea

Settings is the control room for one contractor business.

It should answer three questions without making someone hunt around:

1. What information represents my business?
2. How should the CRM behave for my team and customers?
3. Which services and connections are ready, need attention, or are unavailable on my plan?

A setting appears only when the feature it controls is real. We do not fill Settings with dead pages or "coming soon" cards just to make it look complete.

## What the Settings home looks like

The home page is one clean, scrollable directory grouped by purpose. The groups are visual sections, not seven cards that lead to more menus. Every useful destination remains directly visible as its own card, so a contractor can open Price Book, Taxes, Team, Booking Forms, or another setting without first visiting an intermediate category page.

Each group uses the same bordered-section appearance already used on Client and Request screens: a box with its title sitting across the border. Inside it, destination cards form a responsive grid:

- Four cards per row on a wide desktop
- Three cards per row on a normal desktop
- Two cards per row on a tablet
- One card per row on a phone

Every card contains an icon, a simple name, one short human description, and an arrow showing that it opens a page. When useful, it may also show a status such as **Ready**, **Needs setup**, **Connected**, **Disabled**, or **Not included in your plan**.

A sticky category bar sits below the Settings heading. Clicking a category smoothly scrolls to that section on the same page, and the visible category is highlighted. These controls are jump links, not tabs: all categories and cards remain on the page. On a small screen, the category bar scrolls sideways rather than wrapping into a tall block.

At the top, the signed-in person sees their name, role, and a link to their personal account. This personal shortcut sits outside the business sections. Business settings and personal preferences remain visibly separate.

The contractor app sidebar identifies the current business using the saved organization logo and Business
Profile company name. These replace the generic `Workspace / Contractor CRM` identity. If no logo has been
uploaded, the sidebar uses the product's neutral fallback mark while still showing the company name. This
business branding does not recolor the CRM interface.

The planned groups are:

1. Business
2. Team & access
3. Work
4. Communications
5. Money
6. Customer experience
7. Automations, notifications & connections

Settings search can arrive after enough real destinations exist to make it useful. Returning from a detail page should bring the person back to the same section of the Settings directory.

---

## 1. Business

### Business profile

**What it is for:** The main identity of the contractor business. Information entered here is reused throughout the CRM so the owner does not have to enter it repeatedly.

**What exists here:**

- Business name
- Trade or industry
- Main phone number
- Website
- Short business description or tagline
- Business address
- Operational timezone
- Currency

**Where it is used:** Quotes, invoices, receipts, customer emails, public forms, the client portal, appointment times, and reports.

**Important behavior:** The operational timezone belongs to the contractor. It is separate from Jafar's platform billing timezone.

The business name is the customer-facing trading name, not necessarily the legal entity name used for
future invoicing or payments. The main phone is explicitly customer-facing. Business name, operational
timezone, and currency are required; the remaining fields are optional. Trade uses a searchable list with
an **Other** choice and short custom value.

The business address has one shared customer-visibility choice. When enabled, customer surfaces may show the
full address. When disabled, they show only city and state or region. With no address, they show nothing.
Future Invoice Settings may own a separate legal address; individual documents do not invent their own
Business Profile visibility switches.

### Branding

**What it is for:** Controls how the business looks to its customers.

**What exists here:**

- Logo
- Main brand color
- Optional short tagline

**Where it is used:** Quotes, invoices, receipts, customer emails, booking/request forms, and the client portal.

**Important behavior:** Branding changes customer-facing material. It does not recolor the contractor's CRM interface.

The tagline is edited only in Business Profile. Branding previews it with the logo and color. Customer
templates automatically choose readable foreground and surrounding colors without changing the saved brand
color. **Reset to default** restores the neutral product color.

Published customer documents freeze the business identity and branding shown at publication, including an
immutable copy of the logo. Replacing or removing the current logo changes the portal shell and future
documents, not historical published documents. Logo removal requires confirmation and previews the fallback.

### Business hours

**What it is for:** Records when the business normally operates.

**What exists here:**

- Open or closed for each day
- Up to three opening periods for each open day
- Overnight periods and an explicit **Open 24 hours** choice
- An explicit **By appointment only** state

**Where it is used:** Scheduling, online booking, reminders, and availability.

**Important behavior:** These are regular weekly hours and shared defaults. They are not date-specific holiday
hours and do not claim to restrict booking before Scheduling supports that behavior. Individual booking forms
or team members may later have narrower availability. An overnight period belongs to the day it opens and is
shown with “next day”; periods cannot overlap across midnight.

### Taxes

**What it is for:** Saves the tax rates the business commonly uses.

**What exists here:**

- Named tax rates
- A Business default that may be a saved rate or **No tax**
- Active and inactive rates

**Where it is used:** Quotes and invoices.

**Important behavior:** A property chooses either **Use business default** or a specific saved rate. A property
using the Business default follows future Business-default changes for future drafts; a specifically assigned
rate stays pinned until changed. Existing drafts and published documents keep the named rate and percentage
already copied into them. An individual document may use a different saved or custom rate.

Editing a saved rate changes future drafts for Properties assigned to that rate and explains how many Properties
currently use it before Save. A rate assigned to any Property cannot be permanently deleted. It may be made
inactive, which keeps those Properties pinned but removes it from new selections. Permanent deletion becomes
available only after every affected Property is explicitly reassigned.

A saved rate requires a name and a percentage greater than 0% and no more than 100%, with up to two decimal
places. **No tax** is a separate Business-default choice rather than a saved 0% rate.

Tax setup starts **Not configured**, which is not the same as **No tax**. Staff may prepare a draft while tax is
unconfigured, but a priced Quote cannot be published until an authorized person chooses a saved rate, enters a
one-off named custom rate, or explicitly confirms **No tax**. The blocking message links directly to Taxes.

Any staff member allowed to edit Quote pricing may use a one-off custom rate on that Quote. It never enters the
shared list silently. Only owners and administrators may choose **Save this rate for future use**, which starts
off; saving it does not make it the Business default. Changing a Business default requires confirmation when
Properties inherit it, naming how many will use the new rate for future documents and confirming existing
documents will not change.

---

## 2. Team & access

### Team

**What it is for:** Manages the people who work inside the contractor account.

**What exists here:**

- Active and inactive members
- Member name and contact details
- Role
- Working availability when scheduling supports it

**Typical actions:** Invite a member, change their role, deactivate them, or restore an inactive member.

### Roles & permissions

**What it is for:** Controls what each kind of team member can see and do.

**Examples:**

- Who can see prices, costs, profit, invoices, and payments
- Who can manage customers and work
- Who can manage the Price Book, forms, automations, and business settings
- Who can invite or remove team members

**Important behavior:** People only see Settings destinations they are allowed to use. Hiding a page is not enough; the same permission must protect the action everywhere in the CRM.

### My account

**What it is for:** Personal information and sign-in security for the current user.

**What exists here:**

- Name
- Email used to sign in
- Password and security controls

Business owners cannot edit another person's password.

### Confirmed Part 3 behavior

- Owners and administrators invite team members directly. Jafar controls organization entitlements and seat
  limits but does not perform routine team administration.
- An organization has exactly one Owner. Ordinary role editing cannot demote, deactivate, or remove the Owner.
  Ownership transfer is a separate protected action to an active Administrator.
- Team access uses the standard Administrator, Office, Sales, Field, and Finance roles as understandable
  starting points. Contractors do not create named custom roles. An authorized administrator may make explicit
  permission adjustments for one team member.
- Whether permanent removal may erase identity or historical attribution remains unresolved. Jafar has approved
  both deactivation and an Owner-only permanent action. Permanent removal revokes login and reactivation,
  removes permission settings, and removes personal contact details where legally safe. It preserves the former
  member's name and attribution on completed work, time entries, payments, messages, and audit records so
  history remains truthful. The confirmation explains that the action cannot be undone.
- A team invitation fails safely when its email already belongs to another contractor organization. UCRM does
  not automatically transfer accounts between organizations.
- Invitations expire after seven days. Owners and administrators may resend or cancel a pending invitation;
  resending invalidates every older link. Pending invitations appear separately and consume seats.
- A new invitation is blocked before sending when active plus pending members reach the organization's
  platform-controlled seat limit. The page explains the count and upgrade path. Deactivated members do not
  consume seats; permanent removal frees no additional seat beyond deactivation.
- Inviting a member requires an explicit role choice; no role is silently preselected. Each standard role has
  a short plain-English summary.
- Owners and administrators may adjust permissions for Office, Sales, Field, and Finance members. An
  Administrator cannot edit the Owner's access or grant ownership.
- Permission editing groups controls by understandable capabilities such as Customers, Quotes, Scheduling,
  Costs, Invoices, Payments, and Team. Each capability may expose the detailed controls needed for safe,
  flexible access, but never exposes database permission keys or permits invalid combinations. An information
  control available by hover, keyboard focus, and click explains each capability, its practical effect,
  examples, and dependencies in plain language. Members whose access differs from their role show Adjusted.
- Deactivation shows every affected unfinished assignment and requires the administrator either to reassign
  all eligible work to another active member or deliberately leave it unassigned. Completed work retains its
  original attribution, and reactivation never restores old assignments.
- Invitations use email only in the first release. A delivery failure leaves the invitation pending with a
  visible Delivery failed state and allows resend or cancellation; it never silently creates an unreachable
  account. SMS invitation delivery waits for working messaging setup and consent behavior.
- Only the Owner may promote someone to Administrator or change, deactivate, demote, or permanently remove an
  Administrator. Administrators manage Office, Sales, Field, and Finance members. Nobody edits their own role
  or permissions; the Owner changes only through the protected ownership-transfer flow.
- Changing a role first previews the resulting access and requires choosing either the new role's standard
  access or retaining compatible individual adjustments. Invalid adjustments are removed, and the preview
  names them before Save.
- Owners and administrators may edit another member's display name, work phone, job title, and scheduling
  color. Each member controls their own sign-in email, password, MFA, and security details. A sign-in email
  change requires verification by that member.
- Permanent removal is available only after deactivation and requires the Owner to type the member's name.
  An Administrator must first be demoted by the Owner. The Owner cannot remove themselves through this flow.
- Each member has recent access activity visible to the Owner and Administrators. It records the actor, action,
  date, and meaningful before/after change for invitations, role and permission changes, deactivation,
  restoration, and permanent removal. Passwords and invitation tokens are never recorded.
- Team membership has three clear states: Pending, Active, and Deactivated. An invitee becomes Active only
  after accepting the invitation and establishing sign-in access. Pending members consume seats but have no
  application access.
- An authorized team manager may change a pending invitee's role and permissions without sending a new
  invitation. Changing the email cancels the old invitation and creates a new one for the new identity.
- Restoration is blocked when no seat is available and shows the current seat count and upgrade path.
- Role and permission changes, deactivation, and restoration take effect immediately at the server boundary.
  Deactivation ends active sessions; stale pages or cached data never preserve revoked authority.
- Invitations, role changes, deactivation, restoration, and ownership transfer produce in-app and email
  notifications. One Save containing detailed permission adjustments produces one understandable summary,
  not one message per control.
- A capability unavailable under the organization's platform entitlement appears disabled as Not included in
  your plan with an explanation. Saved adjustments are preserved while unavailable but grant no access unless
  the entitlement returns.
- The current Owner may transfer ownership only to an active Administrator. The Owner confirms with password or
  MFA and sends a request that the recipient must accept. Until acceptance, nothing changes and the Owner may
  cancel. On acceptance, the recipient becomes Owner and the former Owner becomes Administrator.
- Reinviting a permanently removed person's email creates a new membership with new permissions, assignments,
  and access history. It does not restore or attach the former membership, whose historical attribution remains.
- When Scheduling is ready, member availability supports a regular weekly pattern plus dated exceptions such as
  leave, training, or temporary hours. Business Hours describe when the company operates; member availability
  describes when that person can work. Owners and administrators manage any member's availability, and members
  may update their own.
- Availability guides scheduling rather than blocking it. An authorized scheduler may assign an unavailable
  member after a clear warning, and UCRM records who accepted the conflict.
- Before a role or permission save removes access needed by unfinished assignments, UCRM shows the affected
  work and requires the administrator to reassign it or deliberately leave it unassigned. Access is never kept
  merely to support an old assignment.
- Member details, Role & access, and Availability save independently. Nothing changes until that section's Save;
  Cancel restores its saved state. Each section has conflict protection so concurrent editors cannot silently
  overwrite one another.
- Capabilities tied to assignable work use No access, Assigned work only, and All work where meaningful.
  Assigned access reveals only the customer and property information needed for that assignment; prices,
  internal costs and profit, payments, private notes, and unrelated history remain separately protected.
- Standard role starting points are:
  - **Administrator:** Business operations, ordinary team management, and business settings, excluding ownership
    control and authority over other Administrators.
  - **Office:** All customers and operational work, scheduling, Quotes, invoices, communications, and collections,
    without internal cost and profit or Team access by default.
  - **Sales:** Customers, Requests, Pipeline, assessments, and Quotes, including prices but excluding internal
    costs, payments, business-settings management, and Team management.
  - **Field:** Assigned customers, properties, Visits, Job instructions, forms, time, notes, and photos, excluding
    prices, costs, Pipeline, invoices, payments, and business-settings management.
  - **Finance:** Financial customer summaries, Quotes, invoices, payments, and financial reports, excluding
    sales, scheduling, field operations, Team management, and business-settings management.
- The Owner always has full contractor access. Administrator always includes ordinary Team management and
  business-settings management; the Owner may adjust an Administrator's other operational capabilities. A
  person without those administration responsibilities uses a different role.
- Each new feature ships explicit safe role defaults. Owner and Administrator receive necessary administration
  access. Other roles receive only the defaults approved with that feature. Existing personal denials remain,
  and newly introduced sensitive capabilities default off unless deliberately granted.
- Team settings show a capability only when navigation, APIs, and database access enforce it consistently.
  Legacy duplicate keys and unfinished permissions are reconciled during implementation and never shown to
  contractors.

---

## 3. Work

### Price Book

**What it is for:** Stores reusable products and services so estimates, quotes, jobs, and invoices can be created quickly and consistently.

**What exists here:**

- Item name and description
- Product or Service type, with an optional **This service is labor** classification for Services
- Optional unit chosen from searchable common units or entered as a custom unit
- Selling price and internal cost
- Taxable by default, with an explicit **Tax exempt** choice
- Items may be added, changed, or deleted

**Important behavior:** The Price Book is a collection of reusable line-item templates, not an authoritative
product or pricing database. Adding an item to a document copies its current details. The document owns that
copy from then on, so changing or deleting the Price Book item never changes an existing Request, Quote, Job,
or Invoice. A staff member may also create a one-off document line without saving it to the Price Book. Active
item names are unique without regard to capitalization; deleting an item makes its name available again.

Deleting an item requires a short confirmation naming it and explaining that existing document lines remain
unchanged. Confirmation permanently deletes the template and removes it from future selection. A copied unit
remains part of the document line even if the source item is later changed or deleted.

Selling price is the saved customer price. Internal cost is private. Markup is a calculator rather than a third
stored money value: cost and markup can calculate the selling price, while changing cost or selling price
recalculates the displayed markup.

Until Roles & Permissions provides finer control, owners and administrators may add, edit, or delete shared
Price Book items. Any team member allowed to edit Quote pricing may use them. Internal cost and profit data are
never returned to a person who lacks cost visibility.

The Price Book Settings destination is hidden from other roles for now, while eligible Quote editors still use
the picker inside a Quote. Item edits use revision conflict protection. A stale editor reviews the latest value
or discards their changes; an item deleted elsewhere is never silently recreated. The edit view shows the last
editor and time, while full history UI remains deferred.

The first management page searches item names and descriptions; filters by Product, Service, Labor, Taxable,
and Tax exempt; and sorts by name, selling price, or most recently updated. Its paginated list supports add,
edit, and delete without downloading the whole Price Book. CSV import, bulk editing, extra categories, and
photos remain outside this release until separately approved.

Price Book starts empty with a plain explanation and **Add product or service**. Production organizations never
receive guessed starter items; intentional demo organizations may receive explicit demo data.

### Request & booking forms

**What it is for:** Creates public forms customers can use to ask for work or book a time.

**What exists here:**

- Multiple forms for different services or campaigns
- Request form or instant-booking form
- Public link and website embed option
- One default request form and one default booking form
- Title, description, and customer questions
- Required and optional fields
- Photo upload choice
- Bookable services
- Available days and times
- Minimum notice, duration, and arrival window
- Assigned team members
- Confirmation behavior
- Optional redirect after submission

**Important behavior:** A request form creates a lead/request for staff to review. An instant-booking form may create scheduled work or an assessment, depending on its approved setup. They are not the same promise to the customer.

### Quote settings

**What it is for:** Controls the defaults used when staff create a new quote.

**What exists here:**

- Default terms and conditions with safe paragraphs, headings, lists, bold, italic, and links
- Optional business representative name, title, and signature block copied into new Quote drafts
- Target profit margin shown only to staff authorized to see internal cost and profit
- Organization-wide **Require customer signature** choice
- Quote numbering and presentation when those features are ready
- Reusable quote templates when template support is ready

**Important behavior:** Defaults are copied into a new Quote. Changing a default later does not rewrite existing
Quotes or anything the customer already saw. Staff can adjust the copied content on an individual draft Quote.
The business representative is presentation content, not an internal approval workflow or a list of customer
contacts allowed to approve. Target margin is private guidance: an authorized staff member may see the current
margin, the target, and a suggested selling price, but the CRM never changes a price automatically and never
shows cost, profit, target margin, or the suggestion to a customer.

Owners and administrators manage Taxes and Quote defaults until Roles & Permissions provides finer control.
Terms support only the approved safe formatting; arbitrary HTML, images, tables, scripts, and embedded content
are not accepted.

Taxes and Quote Settings destinations are hidden from other roles for now. Tax-rate editors and each independently
saved Quote Settings section show the last editor and time. Writes use revision conflict protection and record
audit events; full history UI remains deferred.

Enabling the business representative block requires a representative name. Title and an uploaded or drawn
signature image are optional. The page previews the customer result; without an image, the typed name and title
still appear. The entire block is copied into a new Quote draft.

Target margin starts **Not set** and is never guessed. When configured, it must be greater than 0% and below
100%. Falling below it provides private guidance only and never blocks saving, sending, approval, or conversion.
The guidance shows the additional revenue and target total but never automatically spreads a price increase
across line items; staff decide which customer prices to change.

Quotes have no Good/Better/Best package system. Target guidance shows the required base Quote margin and each
optional add-on's margin separately. Contractors who need alternative offers create separate Quotes; approving
one never closes another automatically.

Requiring a customer signature starts off. The current policy is copied into each new Quote and frozen when the
Quote is published. Changing the organization setting does not change a customer link already sent. Staff must
deliberately revise and republish an existing Quote to apply a newer signature policy.

Terms, business representative, target margin, and customer-signature policy save independently with separate
conflict protection. A failure in one section does not block another section's valid save, and each successful
change records who changed it and when.

Quote numbering, extra presentation controls, and reusable Quote templates do not appear until their real
behavior is approved and usable. Settings shows no disabled rows or **Coming soon** placeholders for them.

### Job settings

**What it is for:** Controls extra information and field workflows used on jobs.

**Planned destinations:**

- Job custom fields, such as gate code, permit number, or warranty expiry
- Job forms, checklists, and inspection forms
- Scheduling defaults that belong specifically to jobs

These pages appear only when Jobs supports the information end to end.

### Pipeline stages

**What it is for:** Controls how much assessment detail the business sees in its sales Pipeline without
changing Request, Assessment, Quote, Won, or Lost truth.

**What exists here:**

- **Show detailed assessment stages** is off by default. Off shows one Assessment column with the card's real
  scheduling/completion state. On expands it into Assessment unscheduled, Assessment scheduled, and
  Assessment completed.
- A read-only preview shows the resulting five- or seven-column board.
- Protected stages show why they cannot be renamed, reordered, hidden, or removed.
- A later release may add custom follow-up stages within either Requests or Quotes, with safe reassignment and
  dependency checks when a used stage is disabled or removed.

**Important behavior:** Pipeline owns this feature and its behavior contract. Settings provides its
permission-aware home only after the control works end to end. The presentation toggle never changes stored
work state or history. Custom stages never replace system stages. Won remains automatic from the approved
Quote or real Job action; Lost and terminal lifecycle rules remain protected. See
`docs/sales-pipeline-behavior-contract.md`.

---

## 4. Communications

### Email

**What it is for:** Controls the business identity customers see when the CRM sends and receives email.

**What exists here:**

- Customer-facing sender name and address
- Branded sending domain and its readiness
- Additional addresses such as sales or support
- Reply handling and forwarding choices when Communications supports them
- A managed request to change the sending domain

**Important behavior:** Contractors control ordinary names and preferences. Jafar controls provider setup, verification, safety limits, and infrastructure.

### Phone & SMS

**What it is for:** Shows the communication numbers, registration state, and usage available to the business.

**What exists here when ready:**

- Assigned phone numbers
- Messaging registration status
- Calling and texting availability
- Business-wide SMS quiet hours
- Blocked numbers

### SMS usage

**What it is for:** Makes text-message cost and activity understandable.

**What exists here:**

- Current balance
- Approximate messages remaining
- Included monthly amount and message rate
- Sent, delivered, and failed totals
- A history of credits, charges, refunds, and top-ups

### Quick replies

**What it is for:** Saves frequently used messages for the shared inbox.

**What exists here:**

- Reply name
- Channel suitability
- Message body
- Safe placeholders such as customer name and business name

---

## 5. Money

### Invoice settings

**What it is for:** Controls the defaults used for new invoices and customer receipts.

**Planned settings:**

- Invoice numbering and payment terms
- Default notes or instructions
- Receipt behavior
- Customer tipping choice
- Payment reminders through the Automation area

Changes affect new drafts, not previously issued invoices.

### Payments

**What it is for:** Connects and manages the service used to collect customer money.

**What exists here when ready:**

- Connection status
- Supported payment methods
- Deposit and payment collection choices
- Receipt and administrator notification preferences
- Clear explanation when payments are unavailable or not included in the plan

Platform infrastructure and financial provider controls remain with Jafar.

---

## 6. Customer experience

### Client portal

**What it is for:** Controls what customers can do in their secure self-service area.

**Planned choices:**

- View and approve quotes
- Sign and pay deposits
- View and pay invoices
- See appointments and visit history
- Request more work
- Decide which eligible documents appear in portal navigation

Branding comes from Business Profile.

### Reviews

**What it is for:** Controls where happy customers are sent and how review requests behave.

**What exists here when Reputation is ready:**

- Google Business Profile review link
- Review-request wording or template
- Timing and follow-up choices through Automation
- Complaint recovery behavior

---

## 7. Automations, notifications & connections

### Automation

**What it is for:** Handles routine follow-up without requiring the owner to build everything from scratch.

**Built-in presets:**

- Speed to lead
- Missed-call text-back
- Quote follow-up
- Invoice reminders
- Appointment reminders
- No-show follow-up
- No-quote staff reminder
- Booking confirmation
- Job scheduled confirmation
- On-my-way message
- Review request
- Payment receipt

Each preset shows whether it is on, which channels it uses, its steps, delays, and message previews. The owner can turn it on quickly and adjust the details.

Later, advanced users can build custom trigger → condition → action automations. Safe limits and lifecycle rules still apply.

### My notifications

**What it is for:** Lets each person decide how important events reach them.

**What exists here when contractor notifications are ready:**

- App, push, email, and text choices for each event
- Groups such as Critical, Work updates, and Wins
- Personal quiet hours
- Escalation when an urgent alert remains unread
- Optional working status such as In office, On a job, Deep work, or Off duty

Business-wide messages to customers are not controlled here. This page is only for alerts sent to the team member.

### Integrations

**What it is for:** Shows external services connected to the contractor business.

**Examples:** Payments, Messenger, accounting, calendar, and other approved connections.

Every connection shows a plain status:

- Connected
- Needs setup
- Disabled
- Not included in your plan
- Attention needed

Contractors manage ordinary connection choices. Jafar controls platform credentials, availability, provider limits, and safety.

---

## Rules shared by every settings page

1. **Nothing changes until Save is pressed.** Cancel restores the last saved values.
2. **Explain the effect before the field.** People should know where a setting will be used.
3. **Show only permitted settings.** Owners and administrators normally manage business-wide settings; individual users manage their own account and notifications.
4. **Do not rewrite history.** Defaults normally affect new records. Sent quotes, issued invoices, completed work, and historical messages keep the truth from their time.
5. **One source of truth.** Logo, color, timezone, currency, address, and hours are entered once and reused.
6. **No dead destinations.** A page appears when its feature works. Unavailable integrations may appear only when their status and setup path are genuinely useful.
7. **Be honest about readiness.** Use direct language such as Needs setup, Disabled, or Not included in your plan.
8. **Keep platform controls separate.** Contractors manage their own business. Jafar manages plans, infrastructure, provider access, limits, and platform safety elsewhere.

## Confirmed Part 1 behavior

These rules refine the Part 1 delivery contract and win over earlier implementation plans where they differ:

- Every contractor role may read Business Profile, Branding, and Business Hours. Only owners and administrators
  may edit them. Read-only pages explain who can make changes and show the last editor and time.
- Business Profile, Branding, and Business Hours save independently and have separate conflict protection.
  A stale save identifies the newer editor and time and offers review or discard, never blind overwrite.
- Every settings change records who changed what and when. Part 1 surfaces only the latest editor and time;
  full audit-history UI comes later.
- Incomplete setup never blocks the whole CRM. Missing truth blocks only an action that requires it, such as
  money or scheduling work, and links to the exact missing setting.
- Browser timezone and country-derived currency are suggestions that require confirmation; neither is silently
  saved.
- Currency remains editable through internal drafts and locks when the first Quote is published or shared with
  a customer. The locked field explains why and has no ordinary owner override.
- Existing drafts never change automatically after identity, branding, timezone, or currency edits. An
  unpublished draft may offer **Use latest business details** with a preview. Published records never offer it.
- Existing timed appointments keep their real instant when timezone changes and display in the new timezone.
  Date-only work keeps its calendar date. Regular hours keep their written local times. New work uses the new
  timezone.
- Leaving a dirty settings page warns before internal navigation, refresh, or tab close. Navigation never saves.
- Business Hours distinguishes **Not configured**, configured weekly hours, and **By appointment only**.
- The Settings cards avoid decorative readiness badges. Business Profile shows **Incomplete** only when a
  required field is missing; Business Hours shows **Not set** until configured; Branding shows attention only
  for a real failure; Security shows attention only for a real security action.

## Recommended delivery order

### Part 1 — Settings foundation

- Settings home
- Business Profile
- Branding
- Operational timezone, currency, address, and business hours
- My Account and Security entry
- Permission-aware navigation

### Part 2 — Quotes and pricing

- Taxes: saved rates, Business default, Property inheritance, Quote selection, and publish readiness
- Price Book management on the existing catalog foundation, followed by deletion and conflict protection
- Quote terms, business representative, target margin, and customer-signature policy with their Quote consumers
- Quote templates later, when template behavior is approved

### Part 3 — Team and access

- Team members
- Roles and permissions
- Member availability when Scheduling is ready

### Part 4 — Requests and booking

- Multiple request and booking forms
- Public links and form customization
- Availability, assignment, and confirmation behavior

### Part 5 — Feature-owned settings

- Communications, phone, and SMS
- Invoice and payment settings
- Job fields and forms
- Client portal and reviews
- Personal notifications
- Integrations

Each item in Part 5 is delivered with the real feature it controls, not as an empty settings shell.

### Part 6 — Automation

- One shared recipe model powers both presets and build-from-scratch:
  **When → optional If → ordered Then/Wait actions → Stop when**.
- Presets are editable starting points, not a separate or locked system. The UI reveals Basic, Customize, and
  Advanced controls progressively rather than using a free-form node canvas.
- Recipes move through Draft, Active, Paused, and Archived. Saving never activates; activation has a separate
  plain-English impact review. Existing enrollments retain their recipe version while live consent, opt-out,
  payment, reply, terminal-state, entitlement, and abuse checks always use current truth.
- Initial actions are customer email/SMS when their channels are genuinely ready, internal notification, and
  Task creation. Record creation and status-changing actions are added only through individually approved
  lifecycle-safe contracts; Automation never invents approval, payment, or completed work.
- Contractors receive recommended limits and risk warnings without arbitrary product ceilings. Existing
  package defaults and reasoned organization exceptions in `/jafar` control active recipes, steps, customer
  messages, timing, duration, channel allowance, and action availability. Legal/provider/opt-out/idempotency
  protections remain hard platform rules.
- Automation starts with future events. Manual enrollment for one eligible existing record is explicit and
  previews recipient and timeline. Silent retroactive enrollment is unavailable.
- One record may enter relevant recipes concurrently, but activation warns about overlap and runtime prevents
  duplicate or near-simultaneous customer messages. A customer reply pauses customer-facing steps and alerts
  the owner; authorized staff can Pause, Resume, Skip next step, or Stop one enrollment from the record.
- The complete desktop UI includes the Settings destination, Automation home, preset library, full-page
  builder/detail, activation review, Needs attention, cursor-paginated history, record-level controls, and
  centralized package/organization controls in existing `/jafar` surfaces. Loading, empty, error, forbidden,
  disabled, suspended, over-limit, stale-edit, unsaved, failure, keyboard, focus, and desktop browser states
  are part of each owning slice. Part 6 has no mobile or responsive-layout completion gate.
- Retention is platform-controlled through one extensible `/jafar` Data Retention & Cleanup area. Plain-
  English Balanced, Save more storage, Extended, and Custom presets explain Safe, Caution, Important, and
  Protected categories. Shortening retention shows impact and waits seven days; indexed batched cleanup never
  treats customer messages, consent, approvals, payments, or security evidence as disposable Automation logs.
- Quote follow-up is the first execution slice and starts only after actual successful customer delivery,
  never publication alone. Invoice, Job/review, Scheduling, lead, missed-call, receipt, and other presets ship
  with their dependency-ready owning domains rather than appearing as dead Settings controls.
- Website Chat emits the durable session/message/consent context owned by Communications WC8. Its editable
  preset acknowledges in Website Chat, assigns/notifies staff, waits for a response, and may send one consent-
  aware SMS text-back per session; human or AI response cancels it and SMS failure never blocks Website Chat.

## Approved decisions

Jafar approved this product map on 2026-08-21, including:

- The seven Settings groups make sense.
- Business Profile contains the right shared information.
- Quote-specific controls belong under Quote Settings rather than Business Profile.
- Multiple request and booking forms are wanted.
- The proposed automation preset list is right.
- Personal working status is worth keeping for later notification escalation.
- Settings destinations should remain hidden until their underlying feature is usable.
- The contractor sidebar should show the saved organization logo and company name, with a neutral logo
  fallback when the organization has not uploaded one.
- The recommended delivery order is acceptable.

This blueprint is the product map for the Contractor Settings campaign. The campaign roadmap splits it into small, independently testable implementation parts without changing the approved user experience silently.

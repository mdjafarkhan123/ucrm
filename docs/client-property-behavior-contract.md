# Client and Property Behavior Contract

## Purpose

This contract owns approved Client and Property behavior. `docs/PRODUCT.md` owns the wider product and
newer approved task contracts win if a later conflict is intentional.

## Implementation status, 2026-08-17

Approved here does not mean shipped. Built and live: client identity and contacts, the client list, create
and detail, properties with add, edit and remove, notes, tags, files, activity, tenant isolation,
permissions, search, and create-time duplicate warnings.

Approved but not built, each waiting on work objects or invoicing: property deletion guarded by real work,
historical address snapshots, property transfer between clients, the billing address, and client merge,
archive, restore and audit history. Their reactivation triggers live in `Memory/deferred/INDEX.md`.

## Language and relationships

- **Client** is the contractor-facing module and relationship record for a person or company.
- Lead and Customer are lifecycle states of one Client, not separate record types.
- **Property** is a physical service location owned by one Client. A Client may have zero, one, or many.
- Requests, Quotes, Jobs, and Visits identify their Client and relevant Property. Invoice behavior may also
  retain a distinct billing address and immutable address snapshots.
- Client owns the relationship. Property owns location-specific work, contacts, tax behavior, pricing
  memory, geocoding, route information, access notes, and service history.

## Client identity

A Client supports a person or company name, multiple named contacts, phones, and emails, with one primary
phone and email. It also supports lead source, marketing attribution, owner, lead temperature, next
follow-up, tags, notes, files, referrals, balance, and communication preferences.

Phone and email values are normalized for search and duplicate detection. A company still needs a useful
named contact or communication method before a communication-dependent action can proceed.

## Lead conversion

- Staff may create a Lead or Customer directly.
- A Request from an unknown person creates a Lead after duplicate checking.
- A Lead becomes a Customer when a Job is created, an Invoice is sent, or a Quote is approved.
- Conversion preserves the same Client identity and complete history.
- Conversion is durable; cancelling or deleting downstream work does not silently restore Lead status.
- Imports may create Customers directly.

## Property and address behavior

- A Client has no address of its own. Every address belongs to a Property, matching Jobber, whose Edit Client
  form carries no address field at all.
- The address entered in New Client creates the first Property, matching the proven Jobber model.
- A Client may be saved without a Property, but property-scoped work requires one to be selected or created.
- The Client detail Properties table uses the blueprint columns Street, City, State, and Zip.
- A Client may hold many Properties. They are added, edited, and removed from the Properties block on the
  Client detail page, through a dialog that saves itself rather than staging into the page's action bar.
- Naming a Property is optional; an unnamed one is identified by its street.
- Removing a Property is a soft delete that promotes the oldest remaining Property to primary, so a Client
  with any active Property always has exactly one primary. A Client may be left with none.
- Billing Address is identified separately and is not yet implemented. Jobber stores an optional billing
  address on each Property; our schema currently carries a single `is_billing_address` flag, which stays
  unset until invoicing decides the shape.
- Changing a Property never rewrites immutable address snapshots on historical or finalized records.
- Moving a Property between Clients is not an ordinary edit; any future transfer must preserve history.

## Client creation and editing

The approved workspace contains Primary Details, Property Address, Lead Source, Tags, Notes, Attachments,
and Cancel, Save and Create Another, and Save Client actions. Primary Details use First name, Last name,
Email address, Phone number, optional Company name, and communication settings. Property Address uses
Street Address 1, optional Street Address 2, Postal Code, City, State, and Country.

Writes validate before database access. Duplicate candidates are shown before final creation. Exact-match
blocking or authorized override behavior is decided with the duplicate implementation. Client, Property,
note, and attachment writes must be atomic or explicitly retry-safe so partial failure creates no orphan.

## List and detail behavior

The Client list uses Name, Address, Email and Phone, Tags, Status, and Actions. It supports search, approved
filters, stable pagination, row selection, sorting, and permission-aware import, export, merge, archive, and
delete actions. Address shows the primary Property and indicates additional Properties.

The Client header uses Status, Client name, Main Phone, Main Email, Last contact, Lifetime, Open Quotes,
Active Jobs, Call, Message, More actions, and Edit. Lifetime is completed revenue. Open Quotes and Active
Jobs are unambiguous counts unless explicitly labelled as money.

The Details view contains Addresses, Work Overview, Client Schedule, notes, tags, and attachments.
Communication history lives in the Communication view when that campaign supplies it. Work Overview uses
Item, Address, Date, Status, and Amount. Client Schedule uses Schedule, Title, and Assigned.

Unfinished domains do not display fabricated records or working actions. Large histories paginate or link
to their owning domain.

## Consent and communication

Store separate preferences for appointment reminders, quote follow-ups, invoice reminders, job follow-ups,
review requests, and marketing. A legal SMS opt-out overrides every feature and blocks outbound texting
until valid opt-in is recorded. Marketing consent remains distinct from operational communication.

## Duplicate merge

Candidates use normalized phone and email, compatible identity, and address similarity. Merge requires
permission and a conflict preview. It moves relationships transactionally to one survivor, preserves an
audit mapping from merged identities, and never crosses organizations. Similarity alone never authorizes
an automatic merge.

## Archive, deletion, and retention

- Archive is the normal reversible action for an inactive Client and preserves history indefinitely.
- Active Requests and Quotes must be archived or converted, Jobs closed, and Invoices resolved before the
  Client can be archived.
- Creating new work for an archived Client automatically restores the Client to active status.
- Delete moves the Client to Recently Deleted for 30 days. Authorized administrators may restore it.
- After 30 days, an automated purge removes eligible data. Required financial, tax, and audit history is
  retained in minimal or anonymized form without changing historical totals.
- Property removal follows the same historical-safety rule and cannot silently destroy work or financial
  history.
- Delete, restore, purge, archive, unarchive, and merge are audited.

## Security and permissions

Permissions separately protect view, create/edit, archive/restore, delete, merge, import/export, financial
summaries, and sensitive notes, files, or communication history. Every operation is tenant-scoped through
server authorization and RLS. UI visibility is not permission enforcement.

Schema, RLS, permission, and authentication changes require Jafar's explicit approval at their campaign
gate.

## Explicit omissions

This contract does not approve arbitrary custom-field builders, full Client Portal behavior, route
optimization, automatic tax jurisdiction, pricing recommendations, marketing execution, future-domain
status machines, cross-organization transfer, or unlimited inline history. Jobber field names do not
replace the approved UCRM blueprint fields.

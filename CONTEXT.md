# UpliftContractor glossary

## Work coordination

- **Task** — An internal follow-up or coordination item assigned to a team member, optionally due on a date.
  It is not customer work, a service appointment, or a calendar-blocking Event. _Avoid_: Job, Visit, or Event.

## Sales pipeline

- **Opportunity** — The sales-tracking record generated from one real Request or Quote. A Direct job may create
  a closed-only Opportunity for honest Sales Outcomes, but staff never create an Opportunity by hand. Open
  Opportunities appear on the Pipeline; closed ones appear only in outcomes and reporting. _Avoid_: Deal when
  referring to this record.
- **Direct job** — A Job created without a Request or Quote. It never appears on the active Pipeline, but creates
  one separately labelled Closed Won result. It is excluded from Request/Quote conversion percentages.
- **Protected stage** — A Pipeline position whose meaning is established by a real Request, Assessment, or Quote
  fact. Entering it requires the matching domain action; it cannot be renamed or removed.
- **Custom follow-up stage** — An owner-configured Pipeline position used only to organize follow-up inside the
  Request or Quote section. It never replaces source-record status, and a later protected-stage event overrides it.

## Commercial documents

- **Price book** — The organization's reusable Product and Service line-item templates. Adding an item copies
  its current values into a work document; the Price book is never the authoritative source for that document's
  pricing and its items may be added, changed, or deleted independently. _Avoid_: Product database or live price
  source.
- **Labor** — A Service classification for work performed by people. It is not a third Price book item type
  beside Product and Service.

## Files and media

- **File** — One organization-owned original stored once and reusable across records and documents. It is the
  authoritative asset; using it in another place creates another link, not another copy. _Avoid_: Attachment
  when referring to the stored asset itself.
- **Attachment** — One use of a File on a Client, Request, Quote, Job, Visit, Invoice, message, or other record.
  It supplies context without becoming a separate stored copy. _Avoid_: File when referring only to that use.
- **File Manager** — The contractor-wide workspace and complete catalog of the organization's Files. Every
  uploaded or recorded file appears there automatically, regardless of where it entered the product. _Avoid_:
  Client file library when referring to the organization-wide system.

## Client relationships

- **Client** — The contractor's complete relationship with a person or company, whether prospective or paying. _Avoid_: Contact or account when referring to the relationship record.
- **Lead** — A lifecycle state for a Client who has not yet crossed an approved customer-conversion trigger. It is not a separate record type.
- **Customer** — A lifecycle state for a Client who has crossed an approved conversion trigger such as an approved quote, created job, or sent invoice. It is not a separate record type.
- **Property** — A physical service location belonging to a Client. Location-specific work, contacts, tax behavior, pricing memory, and routing attach to the Property. _Avoid_: Client address when referring to a service location.
- **Archive** — A reversible inactive state that preserves the Client and relationship history indefinitely.
- **Recently Deleted** — A 30-day recoverable state before eligible Client data is permanently purged or required financial history is anonymized and retained. _Avoid_: Archive.

## Platform onboarding

- **Prospect** — A contractor business that has submitted the platform onboarding form but does not yet have an UpliftContractor organization, a contractor login, or tenant data.
- **Onboarding application** — The platform-owned record of a prospect's submitted business, administrator, and selected-package information.
- **Payment confirmed** — The Platform Owner has manually verified that the prospect's offsite subscription payment is received. It is not a payment record held or processed by UpliftContractor.
- **Organization** — An active or suspended contractor tenant created only after payment confirmation and successful account provisioning.
- **Initial contractor administrator** — The first user for a newly provisioned organization. This person administers that contractor tenant; the Platform Owner never becomes a tenant member.
- **Activated package** — The package edition applied to an organization at provisioning. It normally matches the prospect's selected edition, but the Platform Owner may correct it to match the edition actually paid for and must record a private reason.
- **Not proceeding** — A platform-owned final prospect outcome used when no account will be created. It is not an organization lifecycle state.
- **Needs attention** — A prospect outcome meaning payment is confirmed but safe account provisioning cannot proceed without an owner resolving a specific problem. It is not an organization lifecycle state.
- **Possible duplicate** — A prospect submission that may represent an existing prospect. It requires owner review; it never authorizes automatic merging or replacement of submitted information.
- **Package** — A platform-owned commercial offer built only in the `/jafar` package builder, with a stable name and public slug. Its visibility, display order, and archived state can change without changing any customer's terms. _Avoid_: Plan, tier.
- **Package edition** — The frozen customer-facing terms of one published revision of a package: capabilities, allowances, included services, highlights, and monthly and yearly USD prices. Revising published terms creates the next edition; it never rewrites an earlier one. _Avoid_: Package version.
- **Package draft** — The single unpublished working copy of a package's next edition. It is saved whole and grants nothing until published.
- **Capability** — A working product area an edition can include, such as Sales pipeline or Website chat. Core capabilities are in every edition; an extra becomes sellable only after its build checks pass. _Avoid_: Feature, when speaking to customers.
- **Allowance** — A business limit Jafar sets in an edition, such as team seats or monthly marketing email. It is distinct from a safety control, which applies equally to every package.
- **Customer highlight** — A short sales line shown on a package card. It never grants access or proves a service is ready.
- **Included service** — Work Uplift delivers as part of a package, such as a premium website or Google Business Profile management, recorded with the edition that promises it.
- **Introductory offer** — A temporary percentage or fixed USD reduction for a set number of monthly periods or the first yearly period. A code is one way to claim it. _Avoid_: Coupon, discount.
- **Agreement** — The dated terms under which an organization receives one package edition: billing interval, agreed price, and any introductory offer. It remains the organization's commercial and access baseline until the Platform Owner explicitly agrees a change. _Avoid_: Subscription, package assignment.
- **Package exception** — A temporary organization-specific difference from the agreed edition, with a reason, start date, and end date. Permanent negotiated terms use a private edition instead.
- **Package charge** — The USD amount due for one service period under an agreement, or for the rest of a period after an immediate package change. _Avoid_: Invoice, which is a contractor's bill to their own customer.
- **Package receipt** — A record of money the Platform Owner confirms was received offsite for an organization's package. _Avoid_: Payment, which is a contractor's customer payment.
- **Package credit** — Money received but not yet applied to a package charge, plus unused paid time returned by an immediate package change. Only the Platform Owner applies or refunds it.
- **Coverage** — The dates for which an organization's access is confirmed as paid or excepted. Coverage moves only by the Platform Owner's explicit confirmation.
- **Service month** — A monthly window counted from the first confirmed coverage start. Monthly allowances reset on it for monthly and yearly agreements alike.
- **Paid-through date** — The last day of an organization's confirmed coverage, for an organization whose package payment is handled outside UpliftContractor.
- **Legacy organization** — An organization created before the paid-prospect onboarding flow. Its current package and paid-through date may be recorded, but missing prospect or payment history is never invented.
- **Onboarding package snapshot** — The exact package edition, billing interval, USD price, offer, and inclusions presented when a prospect submits the public form. It preserves what was selected even if the package is later revised or archived.
- **Platform price** — The USD monthly or yearly price set by UpliftContractor for a package edition. A payment provider may add its own separate fee; that fee is not part of the platform price and is not calculated by UpliftContractor.
- **Organization entitlement** — Platform-controlled access that determines which product capabilities and limits are available to a contractor organization. It is separate from team-member permissions.
- **Team member** — A person with access to a contractor organization, including its owner, office staff, sales staff, field workers, finance staff, or subcontractors. _Avoid_: Employee, when referring to every organization user.
- **Team-member permission** — A contractor-controlled rule describing what one team member may do inside the organization. The contractor owner or administrator normally manages it.
- **Organization Owner** — The single team member with ultimate control of a contractor organization. Ownership is transferred through a protected process, not changed through ordinary role editing.
- **Team-member role** — One of the standard access starting points: Administrator, Office, Sales, Field, or Finance. A team member may have explicit permission adjustments without creating a new named role.
- **Pending team member** — A person invited to an organization who consumes a seat but has no application access until accepting the invitation.
- **Deactivated team member** — A former active member whose access and sessions are revoked while historical attribution is preserved and restoration remains possible.
- **Integration eligibility** — Platform-controlled permission and provider readiness that determine whether an organization may use an integration. It overrides but preserves the contractor's integration preferences.
- **Integration preference** — Contractor-controlled configuration describing how an eligible integration behaves for that organization.
- **Commercial timezone** — The owner-controlled timezone used for paid-through and grace-period deadlines. It is separate from the contractor-controlled operational timezone.
- **Suspension** — A temporary platform lifecycle action that blocks contractor access and pauses new outbound activity while preserving tenant data and required inbound or reconciliation processing.
- **Closure** — A controlled later-phase organization state with an impact preview and recovery period before policy-driven retention, anonymization, or removal. _Avoid_: Immediate deletion.

## Communications billing

- **Provider balance** — The Platform Owner's private prepaid balance with the communications provider. It funds all organization subaccounts and is never an organization asset or contractor-visible balance. _Avoid_: Contractor wallet.
- **Communication balance** — One organization's prepaid USD-equivalent value available for communication usage. One communication credit represents one US dollar, but the contractor interface presents the balance in dollars. _Avoid_: SMS balance, when the value may fund more than SMS.
- **Top-up request** — A contractor- or owner-created claim that an offsite payment was made to fund an organization's communication balance. It creates no spendable value until the Platform Owner confirms receipt.
- **Purchased credit** — Communication value created only after the Platform Owner confirms receipt of an offsite top-up payment. It is distinct from promotional credit.
- **Promotional credit** — Communication value granted by UpliftContractor rather than purchased by the organization. It is spent before purchased credit, may expire, and is never refundable as cash.
- **Monthly communication allowance** — Promotional Credit granted once for an organization's confirmed subscription period. Its default comes from the activated package version, may have a reasoned organization override, and does not roll into a later period.
- **Usage charge** — An immutable deduction from an organization's communication balance for provider-backed usage such as a message, call, or phone number.
- **Credit adjustment** — A reasoned immutable correction or refund entry in the communication ledger. _Avoid_: Balance edit.
- **Outstanding communication usage** — Provider-billed communication cost that could not be paid from an organization's available balance. It is not spendable credit; later Purchased Credit settles it before increasing the spendable balance.
- **Organization SMS mode** — The Platform Owner-controlled maximum SMS capability for an organization: Disabled, Notifications Only, or Two-way SMS. Contractor preference may use a lower mode but never exceed it. _Avoid_: One-way SMS.

## Customer messaging

## Reputation and reviews

- **Review request** — One contractor-initiated request for feedback linked to a completed Job and a Client contact. It may be sent automatically by the review-request automation or deliberately from a completed Job or Client page. _Avoid_: Google review when the customer has only been invited, not confirmed to have posted publicly.
- **Review-request automation** — The contractor-configured SMS sequence that enrols eligible completed work into a Review request, sends its chosen messages, and stops when its outcome is known. _Avoid_: Marketing campaign when referring to the post-work review sequence.
- **Review routing** — The contractor's configured rule that sends a selected rating on the UCRM feedback page to the public Google destination or to private feedback. _Also called_: Review gate.
- **Private feedback** — A customer's answers to the contractor's private feedback form after a Review request. It is not a public Google review and is visible only to authorized contractor team members.
- **Recovery item** — The private work item created from submitted Private feedback. It carries the customer, related Job, rating, answers, owner/assignee, and resolution state. _Avoid_: Review when referring to the contractor's private service-recovery work.
- **Review activity** — The factual history of a Review request: scheduled, sent, delivery result, UCRM feedback-page open, continued-to-Google click, private-feedback submission, cancellation, or other stop reason. A continued-to-Google click is not proof of a published Google review.

- **Contact Widget** — The organization-branded website launcher that may offer Website Chat and configured external contact options. It is the installed customer-facing container, not a conversation channel. _Avoid_: Website Chat when referring to the whole launcher or channel picker.
- **Website Chat** — UpliftContractor's owned persistent website-messaging channel whose conversations enter the organization's Conversations workspace. _Avoid_: Live Chat when immediate human availability is not guaranteed.
- **External contact option** — A contractor-configured destination such as WhatsApp or Messenger that opens outside UpliftContractor and does not bring the resulting messages into Conversations. _Avoid_: Connected channel.
- **Connected channel** — A provider-backed messaging channel whose inbound and outbound activity is integrated into UpliftContractor Conversations. A link that merely opens another application is not connected.
- **Website Chat session** — One visitor-initiated Website Chat exchange associated with its source widget and, after the first accepted message, a Client. Separate visits may become separate sessions without splitting the Client's overall Conversations history.
- **Accepted Website Chat conversation** — A new Website Chat session whose identified visitor has successfully sent the first message. It is the unit counted by the organization's Website Chat conversation allowance; forms, blocked spam, retries, and later messages in that session are not additional accepted conversations.
- **Website Chat availability** — A team member's explicit readiness to receive live Website Chat assignments. It is distinct from business hours, application presence, and whether a widget publicly displays availability.

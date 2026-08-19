# UpliftContractor glossary

## Work coordination

- **Task** — An internal follow-up or coordination item assigned to a team member, optionally due on a date.
  It is not customer work, a service appointment, or a calendar-blocking Event. _Avoid_: Job, Visit, or Event.

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
- **Activated package** — The package applied to an organization at provisioning. It normally matches the prospect's selected package, but the Platform Owner may correct it to match the package actually paid for and must record a private reason.
- **Not proceeding** — A platform-owned final prospect outcome used when no account will be created. It is not an organization lifecycle state.
- **Needs attention** — A prospect outcome meaning payment is confirmed but safe account provisioning cannot proceed without an owner resolving a specific problem. It is not an organization lifecycle state.
- **Possible duplicate** — A prospect submission that may represent an existing prospect. It requires owner review; it never authorizes automatic merging or replacement of submitted information.
- **Package** — A platform-owned commercial offering defined only in the `/jafar` package-management area. It is the single source of truth for what a prospect may select and what can be activated for an organization.
- **Package version** — The dated, immutable record of a package's price, inclusions, and limits at a point in time. A later package edit creates a new version; it does not rewrite prior commercial terms.
- **Package exception** — A time-bound or permanent organization-specific difference from the activated package. It is explicitly recorded and does not redefine the package.
- **Activated package version** — The specific package version an organization bought. It remains its commercial and access baseline until the Platform Owner explicitly changes the organization to another version.
- **Paid-through date** — The last date of paid access recorded by the Platform Owner for an organization whose subscription payment is handled outside UpliftContractor.
- **Legacy organization** — An organization created before the paid-prospect onboarding flow. Its current package and paid-through date may be recorded, but missing prospect or payment history is never invented.
- **Onboarding package snapshot** — The exact package version, USD price, and inclusions presented when a prospect submits the public form. It preserves what was selected even if the package is later revised or retired.
- **Platform price** — The fixed USD monthly price set by UpliftContractor for a package. A payment provider may add its own separate fee; that fee is not part of the platform price and is not calculated by UpliftContractor.
- **Organization entitlement** — Platform-controlled access that determines which product capabilities and limits are available to a contractor organization. It is separate from team-member permissions.
- **Team member** — A person with access to a contractor organization, including its owner, office staff, sales staff, field workers, finance staff, or subcontractors. _Avoid_: Employee, when referring to every organization user.
- **Team-member permission** — A contractor-controlled rule describing what one team member may do inside the organization. The contractor owner or administrator normally manages it.
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

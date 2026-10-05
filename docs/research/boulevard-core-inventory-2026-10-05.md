# Boulevard inventory — Core operations and booking

**Accessed:** 2026-10-05. **Status:** Public-source inventory, not an approved product specification.

Read the [inventory guide](boulevard-feature-landscape-2026-10-05.md) for coverage, confidence, release status and gaps. Each row has its own primary source and the source-reported update date. An update date is not a feature launch date. Feature existence is confirmed by public documentation; detailed parity and our implementation remain unverified.

All rows: **release Unassigned; delivery Needs research**. Multi-location capabilities remain later under the already agreed scope. Most operational features are shared across appointment businesses; clinical entries require clinical configuration, and explicit beauty, enterprise, hardware and partner restrictions are noted. This relevance classification does not assert identical entitlements across every plan.


## BL-01

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-01.01 | Staff accounts and service-provider profiles | [Adding New Staff](https://support.boulevard.io/en/articles/5941423-adding-new-staff) · 2025-09-03 | Shared; bookable calendars have plan limits. |
| BL-01.02 | Job roles | [Staff Roles](https://support.boulevard.io/en/articles/5941382-staff-roles) · 2025-10-17 | Job role and access permissions are distinct. |
| BL-01.03 | Granular permission groups | [Granular permission groups](https://support.boulevard.io/en/articles/11662777-granular-permission-groups) · 2026-08-25 | Includes location scope; replaces older privilege terminology. |
| BL-01.04 | Default access groups | [Default Roles & Permission Groups](https://support.boulevard.io/en/articles/13382959-default-roles-permission-groups) · 2026-06-22 | Starting configurations, not our approved roles. |
| BL-01.05 | Published staff shifts | [Schedule: Publishing and Editing Staff Shifts](https://support.boulevard.io/en/articles/5941438-schedule-publishing-and-editing-staff-shifts) · 2025-03-06 | Availability depends on published schedules. |
| BL-01.06 | Clock-in and edited timecards | [Time Clock and Timecards](https://support.boulevard.io/en/articles/5941378-time-clock-and-timecards) · 2026-10-01 | Staff access and edit permissions need P2 rules. |
| BL-01.07 | Commissions and compensation | [Commission and Compensation](https://support.boulevard.io/en/articles/5941415-commission-and-compensation) · 2026-10-01 | Pay calculations; not evidence of a payroll filing service. |
| BL-01.08 | Commission reassignment | [Commission Swap](https://support.boulevard.io/en/articles/9861681-commission-swap) · 2026-09-14 | Changing commission attribution is distinct from refunding a sale. |
| BL-01.09 | Suspend, deactivate and force logout | [Logging Out, Suspending, and Deactivating Users](https://support.boulevard.io/en/articles/5941450-logging-out-suspending-and-deactivating-users) · 2026-10-04 | Account lifecycle and record retention need separate rules. |
| BL-01.10 | Staff appointment notifications | [Staff Communication Preferences](https://support.boulevard.io/en/articles/5941348-staff-communication-preferences) · 2025-07-18 | Staff messages are separate from client notification preferences. |
| BL-01.11 | Payroll data handoff | [Payroll](https://support.boulevard.io/en/articles/5941315-payroll) · 2026-10-04 | Exports commission, tips and hours; no combined payroll calculation, overtime or wage/salary processing. |
| BL-01.12 | Service cost deduction before commission | [Business Service Charges](https://support.boulevard.io/en/articles/5941510-business-service-charges) · 2025-05-13 | Per-service/location commission basis; source is filed under legacy reports but describes an operating setting. |

## BL-02

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-02.01 | Client profile and visit history | [Client Profiles](https://support.boulevard.io/en/articles/5941460-client-profiles) · 2026-09-29 | Shared profile data; clinical access has additional restrictions. |
| BL-02.02 | Notes about a client | [Client Notes](https://support.boulevard.io/en/articles/5941455-client-notes) · 2026-08-25 | Free text is not a structured clinical safety check. |
| BL-02.03 | Personal service price and duration | [Client Accommodations](https://support.boulevard.io/en/articles/5941448-client-accommodations) · 2025-11-04 | Applies to future staff-created and online bookings. |
| BL-02.04 | Booking alerts | [Scheduling Alerts](https://support.boulevard.io/en/articles/5941470-scheduling-alerts) · 2025-11-04 | Staff-facing warnings; not proof of a hard booking block. |
| BL-02.05 | Block online booking | [Blocking a Client](https://support.boulevard.io/en/articles/5941418-blocking-a-client) · 2025-11-04 | Does not imply every staff action is prohibited. |
| BL-02.06 | Merge duplicate clients | [Merging Client Profiles](https://support.boulevard.io/en/articles/5941428-merging-client-profiles) · 2026-10-01 | Irreversibility and external prescription records require P2 attention. |
| BL-02.07 | Referral source attribution | [Referral Sources](https://support.boulevard.io/en/articles/5941402-referral-sources) · 2026-10-01 | Separate from the client reward program. |
| BL-02.08 | Appointment, order and client tags | [Tags](https://support.boulevard.io/en/articles/5941367-tags) · 2026-05-14 | Shared categorization across records. |
| BL-02.09 | Client search | [Global Search Bar](https://support.boulevard.io/en/articles/5941429-global-search-bar) · 2025-11-04 | Search is a navigation capability, not a separate customer database. |
| BL-02.10 | Client Wallet | [Client Profile: Wallet Overview](https://support.boulevard.io/en/articles/12737024-client-profile-wallet-overview) · 2025-11-20 | Cards, credit, vouchers, gift cards and product units; replaces Payment Methods wording. |
| BL-02.11 | Saved payment cards | [Managing Credit Card Details](https://support.boulevard.io/en/articles/5941462-managing-credit-card-details) · 2025-11-04 | Card handling belongs in payment-specific controls. |
| BL-02.12 | Credit balance adjustments | [Account Credit: Adjustments](https://support.boulevard.io/en/articles/5978297-account-credit-adjustments) · 2026-10-04 | Permission-sensitive financial operation. |
| BL-02.13 | Transfer credit between clients | [Transferring Account Credit Between Clients](https://support.boulevard.io/en/articles/12902126-transferring-account-credit-between-clients) · 2025-11-21 | Distinct from sharing a membership; audit and refund rules need P2. |
| BL-02.14 | Client photo gallery | [Photo Gallery](https://support.boulevard.io/en/articles/8944888-photo-gallery) · 2025-09-18 | Photo access differs from ordinary client details. |
| BL-02.15 | Loose client document uploads | [Client Profile: File uploader](https://support.boulevard.io/en/articles/11583407-client-profile-file-uploader) · 2025-09-18 | Article identifies advanced charting/medspa entitlement. |
| BL-02.16 | Client list and audiences | [Clients & Audiences](https://support.boulevard.io/en/articles/9077071-clients-audiences) · 2026-01-06 | Audience access and location scope matter. |

## BL-03

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-03.01 | Service categories and catalog | [Services and Categories](https://support.boulevard.io/en/articles/5941383-services-and-categories) · 2026-07-07 | Assigned historical services cannot simply be deleted. |
| BL-03.02 | Service add-ons | [Add-On Services](https://support.boulevard.io/en/articles/6584601-add-on-services) · 2026-03-06 | Optional service additions; different from paid software add-ons. |
| BL-03.03 | Service modifiers | [Service Modifiers](https://support.boulevard.io/en/articles/5941408-service-modifiers) · 2024-12-30 | Price/time options within a service, not separate bookings. |
| BL-03.04 | Active service duration | [Service Timing Options](https://support.boulevard.io/en/articles/5941395-service-timing-options) · 2023-07-13 | Provider is occupied during active treatment. |
| BL-03.05 | Processing time | [Service Timing Options](https://support.boulevard.io/en/articles/5941395-service-timing-options) · 2023-07-13 | Client remains occupied while provider may serve another client. |
| BL-03.06 | Finishing and transition time | [Service Timing Options](https://support.boulevard.io/en/articles/5941395-service-timing-options) · 2023-07-13 | Finishing work and cleanup buffers are distinct intervals. |
| BL-03.07 | Location service settings and taxes | [Advanced Service Customization](https://support.boulevard.io/en/articles/5941407-advanced-service-customization) · 2026-07-07 | Changes do not rewrite existing booked appointments. |
| BL-03.08 | Staff service price and duration | [Advanced Service Customization: Staff Level](https://support.boulevard.io/en/articles/7981471-advanced-service-customization-staff-level) · 2025-09-18 | Staff overrides coexist with service defaults and client accommodations. |
| BL-03.09 | Ordering multiple services | [Service Scheduling Order](https://support.boulevard.io/en/articles/8923519-service-scheduling-order) · 2026-07-07 | Booking sequence affects availability. |
| BL-03.10 | Restricted online availability | [Restricting Appointment Availability](https://support.boulevard.io/en/articles/5941449-restricting-appointment-availability) · 2025-07-18 | Booking visibility is configurable. |

## BL-04

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-04.01 | Calendar configuration | [Calendar Settings](https://support.boulevard.io/en/articles/9845474-calendar-settings) · 2026-06-04 | Time intervals, colors and visible hours. |
| BL-04.02 | Create staff-booked appointments | [Adding New Appointments](https://support.boulevard.io/en/articles/5941381-adding-new-appointments) · 2025-11-04 | Staff flow differs from self-booking. |
| BL-04.03 | Calendar views | [Using the Calendar View](https://support.boulevard.io/en/articles/5941397-using-the-calendar-view) · 2026-03-13 | Scheduling surface; not a separate booking engine. |
| BL-04.04 | Requested service provider | [Requested Appointments](https://support.boulevard.io/en/articles/5941413-requested-appointments) · 2026-10-01 | Records client preference for a provider. |
| BL-04.05 | Recurring appointments | [Recurring (Standing) Appointments](https://support.boulevard.io/en/articles/5941424-recurring-standing-appointments) · 2023-07-13 | Staff-created; conflicts are not flagged in the documented flow. |
| BL-04.06 | Prebook the next visit | [Prebooking Appointments](https://support.boulevard.io/en/articles/5941405-prebooking-appointments) · 2026-10-01 | Separate from a recurring series. |
| BL-04.07 | Rooms and equipment | [Resource Scheduling](https://support.boulevard.io/en/articles/5941355-resource-scheduling) · 2026-09-22 | Resource hours and service assignment constrain availability. |
| BL-04.08 | Group self-booking | [Group Booking](https://support.boulevard.io/en/articles/7922463-group-booking) · 2025-09-18 | Documented group creation is online-only; group rescheduling needs staff. |
| BL-04.09 | Reschedule appointments | [Rescheduling Appointments](https://support.boulevard.io/en/articles/6950738-rescheduling-appointments) · 2025-09-18 | Move existing bookings rather than silently making duplicates. |
| BL-04.10 | Cancel and track cancellations | [Canceling Appointments](https://support.boulevard.io/en/articles/5941385-canceling-appointments) · 2025-08-22 | Cancellation history and charging are separate actions. |
| BL-04.11 | Cancelled-appointment list | [Cancelled Appointments List](https://support.boulevard.io/en/articles/5941422-cancelled-appointments-list) · 2026-05-15 | Recovery and follow-up surface. |
| BL-04.12 | Blocked time | [Time Blocks](https://support.boulevard.io/en/articles/5941379-time-blocks) · 2026-10-01 | Supports staff unavailability; permission consistency matters on mobile. |
| BL-04.13 | Minimum and maximum booking lead time | [Scheduling Rules](https://support.boulevard.io/en/articles/5941362-scheduling-rules) · 2023-12-14 | Online booking window controls. |
| BL-04.14 | Waitlist | [Waitlist](https://support.boulevard.io/en/articles/5941433-waitlist) · 2023-07-13 | Online and staff entry; online join requires a card. Do not assume automatic slot assignment. |
| BL-04.15 | Front-desk visit stages | [Using the Front Desk View](https://support.boulevard.io/en/articles/5941360-using-the-front-desk-view) · 2026-06-27 | Tracks arrival and service progress. |
| BL-04.16 | Appointment status and preview | [Appointment Status Icons](https://support.boulevard.io/en/articles/5941417-appointment-status-icons) · 2026-09-11 | Confirmation, arrival and checkout must remain distinguishable. |
| BL-04.17 | Merge same-day appointments | [Merging Multiple Appointments](https://support.boulevard.io/en/articles/5941404-merging-multiple-appointments) · 2025-09-02 | Changes appointment grouping; group checkout is separately inventoried. |
| BL-04.18 | Update appointment tickets | [Updating Tickets](https://support.boulevard.io/en/articles/5941437-updating-tickets) · 2023-07-17 | Service, price, product and time edits. |
| BL-04.19 | Cancellation deadline and fees | [Cancellation Policies and Fees](https://support.boulevard.io/en/articles/5941349-cancellation-policies-and-fees) · 2025-11-14 | Configurable window and percentage/fixed fee; capped at appointment value in documented behavior. |

## BL-05

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-05.01 | Appointment checkout | [Appointment Checkout](https://support.boulevard.io/en/articles/5941386-appointment-checkout) · 2026-07-28 | Finalizes payment and reporting; exiting before completion can leave follow-up unfinished. |
| BL-05.02 | Group checkout | [Group Checkout](https://support.boulevard.io/en/articles/5941426-group-checkout) · 2025-07-22 | Separate from group booking creation and unsupported in mobile-only checkout. |
| BL-05.03 | Retail-only sales | [Retail Only Orders](https://support.boulevard.io/en/articles/5941464-retail-only-orders) · 2025-11-25 | Sale without an appointment. |
| BL-05.04 | Gratuity-only sales | [Gratuity Only Orders](https://support.boulevard.io/en/articles/12860771-gratuity-only-orders) · 2026-10-01 | Separate transaction without a service sale. |
| BL-05.05 | Edit services during checkout | [Add and Edit Services at Checkout](https://support.boulevard.io/en/articles/10414719-add-and-edit-services-at-checkout) · 2025-09-18 | A changed bill may differ from the originally booked service. |
| BL-05.06 | Offers and promotion codes | [Offers](https://support.boulevard.io/en/articles/5941388-offers) · 2026-10-01 | Distinct from manual discounts. |
| BL-05.07 | Manual discounts and reasons | [Discounts](https://support.boulevard.io/en/articles/5941425-discounts) · 2026-10-01 | Permission-sensitive price changes; reasons provide accountability. |
| BL-05.08 | Partial payments and remaining balances | [Partial Payments](https://support.boulevard.io/en/articles/5941430-partial-payments) · 2026-07-28 | Not the same as third-party financing. |
| BL-05.09 | Deposits and prepayments | [Pre-Payments and Deposits](https://support.boulevard.io/en/articles/5941467-pre-payments-and-deposits) · 2026-04-09 | Stored as account credit; online deposits require credit/debit cards. |
| BL-05.10 | Redeem account credit | [Account Credit](https://support.boulevard.io/en/articles/5941435-account-credit) · 2025-11-21 | Credit is a liability/payment balance, not an ordinary discount. |
| BL-05.11 | Custom payment methods | [Custom Payment Types](https://support.boulevard.io/en/articles/5941387-custom-payment-types) · 2026-10-01 | Recording an external payment does not process it. |
| BL-05.12 | Trade/barter transactions | [Trade Transactions](https://support.boulevard.io/en/articles/5941453-trade-transactions) · 2026-10-01 | Special recording flow, separate from collecting money. |
| BL-05.13 | Full and partial refunds | [Issuing Refunds](https://support.boulevard.io/en/articles/5941439-issuing-refunds) · 2026-07-28 | Refund verification is separately documented; payment-method limits need P2. |
| BL-05.14 | Void orders | [Voiding Orders](https://support.boulevard.io/en/articles/5941479-voiding-orders) · 2025-11-15 | Different from a refund; stock and stored value need reconciliation. |
| BL-05.15 | Verify payments and refunds | [Verifying Payments](https://support.boulevard.io/en/articles/5941372-verifying-payments) · 2025-11-04 | Operational evidence before assuming collection succeeded. |
| BL-05.16 | Order management and closeout | [Orders and Closeout](https://support.boulevard.io/en/articles/5941474-orders-and-closeout) · 2025-09-10 | End-of-day reconciliation, not only appointment status. |
| BL-05.17 | Cash register movements | [Cash Register: General Use](https://support.boulevard.io/en/articles/5941486-cash-register-general-use) · 2025-06-04 | Track cash activity and drawer closeout. |
| BL-05.18 | Sell and redeem gift cards | [Gift Cards: Selling, Applying, and Refunding](https://support.boulevard.io/en/articles/5941414-gift-cards-selling-applying-and-refunding) · 2026-07-28 | Digital/physical value has separate liability and refund behavior. |
| BL-05.19 | Adjust or deactivate gift cards | [Gift Cards: Adjustments & Deactivating](https://support.boulevard.io/en/articles/5941419-gift-cards-adjustments-deactivating) · 2025-11-04 | Privileged stored-value changes. |
| BL-05.20 | Receipt delivery and printing | [Receipts: Sending, Printing, and Saving](https://support.boulevard.io/en/articles/5941488-receipts-sending-printing-and-saving) · 2024-12-16 | Not a formal unpaid-invoice workflow. |
| BL-05.21 | Receipt notes | [Receipt Notes](https://support.boulevard.io/en/articles/5941459-receipt-notes) · 2024-11-19 | Business-specific receipt content. |
| BL-05.22 | Print appointment tickets | [Printing Tickets](https://support.boulevard.io/en/articles/5941393-printing-tickets) · 2023-07-13 | Operational printout, separate from a payment receipt. |
| BL-05.23 | Discount reason catalog | [Discount Reasons](https://support.boulevard.io/en/articles/5941352-discount-reasons) · 2026-10-04 | Deleting a reason preserves historical reporting; plan-availability wording conflicts with pricing catalog. |

## BL-06

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-06.01 | Recurring membership plans | [Memberships: Creating a Membership Plan](https://support.boulevard.io/en/articles/10012451-memberships-creating-a-membership-plan) · 2026-05-05 | Recurring billing, benefits and agreements require a coherent P2 contract. |
| BL-06.02 | Sell memberships online and in-store | [Selling Membership Plans In-Store & Online](https://support.boulevard.io/en/articles/10015460-selling-membership-plans-in-store-online) · 2025-11-21 | Enrollment channel affects customer experience. |
| BL-06.03 | Membership billing failures and recovery | [Memberships: Managing Billing](https://support.boulevard.io/en/articles/8619158-memberships-managing-billing) · 2026-10-01 | Past-due alerts, retries and card updates; digital wallets excluded from membership purchases. |
| BL-06.04 | Change a membership plan | [Updating Memberships](https://support.boulevard.io/en/articles/8864471-updating-memberships) · 2025-09-18 | Price/agreement changes affect new sales; benefit changes can affect later renewals. |
| BL-06.05 | Manage a client's membership | [Memberships: Client Profile](https://support.boulevard.io/en/articles/10015361-memberships-client-profile) · 2025-10-29 | Track the individual subscription rather than just the catalog plan. |
| BL-06.06 | Client cancellation and business settings | [Membership settings](https://support.boulevard.io/en/articles/11101465-membership-settings) · 2025-09-18 | Portal cancellation or email request; scheduled cancellation rules require P2 review. |
| BL-06.07 | Prepaid packages | [Packages](https://support.boulevard.io/en/articles/10015766-packages) · 2026-10-04 | Service vouchers or unrestricted credit; not a clinical treatment plan. |
| BL-06.08 | Sell packages online and in-store | [Packages: Selling In-Store & Online](https://support.boulevard.io/en/articles/10548885-packages-selling-in-store-online) · 2025-11-21 | Distinct from automatic membership renewal. |
| BL-06.09 | Sell and redeem during one visit | [Selling and Redeeming a Membership or Package In-Store on the Same Day](https://support.boulevard.io/en/articles/12901962-selling-and-redeeming-a-membership-or-package-in-store-on-the-same-day) · 2025-11-21 | Same-day sale/redemption is explicitly documented. |
| BL-06.10 | Manage service vouchers | [Managing Vouchers](https://support.boulevard.io/en/articles/5941364-managing-vouchers) · 2026-03-03 | Benefit balances differ from money credit and prepaid product units. |
| BL-06.11 | Loyalty earning and redemption | [Loyalty Program App: Earning Points, Redeeming Points & Reporting](https://support.boulevard.io/en/articles/5941351-loyalty-program-app-earning-points-redeeming-points-reporting) · 2026-09-29 | Separate from membership benefits and referral credit. |
| BL-06.12 | Configure loyalty program | [Loyalty Program App: Setup & Management](https://support.boulevard.io/en/articles/5941547-loyalty-program-app-setup-management) · 2026-09-29 | Article says clients cannot view their points; avoid assuming portal visibility. |
| BL-06.13 | Reward client referrals | [Client Referral Program](https://support.boulevard.io/en/articles/9844780-client-referral-program) · 2026-10-01 | Referrer reward follows referred client's first completed appointment; clinical suitability needs review. |

## BL-07

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-07.01 | Product catalog and categories | [Products and Inventory](https://support.boulevard.io/en/articles/5941416-products-and-inventory) · 2025-09-02 | Retail products and consumed service products are different uses. |
| BL-07.02 | Create products | [Adding New Products](https://support.boulevard.io/en/articles/5941357-adding-new-products) · 2026-08-10 | Catalog identity, pricing and inventory configuration. |
| BL-07.03 | Product categories | [Product Categories](https://support.boulevard.io/en/articles/7974573-product-categories) · 2025-09-18 | Organizes catalog and reporting. |
| BL-07.04 | Stock adjustments | [Adjusting Inventory Quantities](https://support.boulevard.io/en/articles/5941380-adjusting-inventory-quantities) · 2026-10-01 | Record quantity changes separately from sales. |
| BL-07.05 | Receive stock | [Receiving Inventory and Adjusting Stock](https://support.boulevard.io/en/articles/5941356-receiving-inventory-and-adjusting-stock) · 2023-07-13 | Receipt of goods updates quantities. |
| BL-07.06 | Suppliers | [Suppliers](https://support.boulevard.io/en/articles/5941370-suppliers) · 2025-06-06 | Supplier records support purchasing. |
| BL-07.07 | Purchase orders | [Purchase Orders](https://support.boulevard.io/en/articles/5941371-purchase-orders) · 2025-11-06 | Order, receive and reconcile supplied products. |
| BL-07.08 | Product returns and exchanges | [Product Returns and Exchanges](https://support.boulevard.io/en/articles/5941403-product-returns-and-exchanges) · 2025-09-17 | Financial refund and physical stock treatment must stay aligned. |
| BL-07.09 | Product consumption and usage pricing | [Tracking and charging for products used during services](https://support.boulevard.io/en/articles/5941350-tracking-and-charging-for-products-used-during-services) · 2026-10-01 | Product usage attached to a service; not proof of lot/expiry traceability. |
| BL-07.10 | Prepaid product units | [Prepaid Product Units](https://support.boulevard.io/en/articles/10055190-prepaid-product-units) · 2026-10-04 | One usage product per service; multiple products require add-on services in the documented approach. |

## BL-10

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-10.01 | Notification settings | [Client Notifications](https://support.boulevard.io/en/articles/8447955-client-notifications) · 2026-09-29 | Transactional notifications differ from marketing consent. |
| BL-10.02 | Booking confirmation emails | [Appointment Booking Confirmations](https://support.boulevard.io/en/articles/8447995-appointment-booking-confirmations) · 2026-07-28 | Client receives booking details and relevant links. |
| BL-10.03 | Booking confirmation texts | [Booking confirmation texts / FAQ](https://support.boulevard.io/en/articles/8447942-booking-confirmation-texts-faq) · 2025-09-18 | Requires messaging setup; include form links when configured. |
| BL-10.04 | Appointment email reminders | [Appointment Reminder Notifications](https://support.boulevard.io/en/articles/8448164-appointment-reminder-notifications) · 2026-07-28 | Reminder schedule and content settings. |
| BL-10.05 | Basic two-day reminders | [Basic 2 Day Reminder Notifications](https://support.boulevard.io/en/articles/8545175-basic-2-day-reminder-notifications) · 2025-09-18 | Baseline reminder behavior; reconcile with configurable reminders. |
| BL-10.06 | Same-day text reminders | [Same-day reminder texts / Setup & FAQ](https://support.boulevard.io/en/articles/8387223-same-day-reminder-texts-setup-faq) · 2025-09-18 | Separate from confirmation texts. |
| BL-10.07 | Automatic receipts | [Order receipts](https://support.boulevard.io/en/articles/10157467-order-receipts) · 2025-09-18 | Email/text delivery depends on configuration and contact availability. |
| BL-10.08 | Rating requests | [Rating requests](https://support.boulevard.io/en/articles/10207593-rating-requests) · 2025-09-18 | Feedback request is not proof of public-review publishing. |
| BL-10.09 | After-hours text responses | [After-hours response texts](https://support.boulevard.io/en/articles/10911321-after-hours-response-texts) · 2025-09-18 | Business-hours based reply, separate from staff Away mode. |
| BL-10.10 | Service-specific client instructions | [Client Instructions](https://support.boulevard.io/en/articles/8447983-client-instructions) · 2025-09-18 | Pre/post-care wording needs clinical review. |
| BL-10.11 | Notification branding | [Client Notification Email Themes](https://support.boulevard.io/en/articles/13179657-client-notification-email-themes) · 2026-02-24 | Theme across transactional emails. |
| BL-10.12 | Conceal service details in email | [HIPAA-Safe email setting](https://support.boulevard.io/en/articles/13179686-hipaa-safe-email-setting) · 2025-12-17 | Sensitive details remain behind the portal; not blanket email compliance. |
| BL-10.13 | Review and manage appointment feedback | [Appointment Ratings](https://support.boulevard.io/en/articles/5941390-appointment-ratings) · 2025-04-02 | Article excludes Essentials while current pricing lists ratings for it; entitlement unresolved. |

## BL-11

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-11.01 | Website booking overlay | [The Client Booking Experience](https://support.boulevard.io/en/articles/5941525-the-client-booking-experience) · 2025-09-22 | Customer service/provider/time selection and checkout-related steps. |
| BL-11.02 | Recommended appointment times | [Precision Scheduling™](https://support.boulevard.io/en/articles/6110033-precision-scheduling) · 2025-07-18 | Optimizes available slots; not a capacity guarantee. |
| BL-11.03 | Adjust scheduling recommendations | [Precision Scheduling™ - Making Adjustments](https://support.boulevard.io/en/articles/11776503-precision-scheduling-making-adjustments) · 2026-01-12 | Configurable behavior must fit real service durations. |
| BL-11.04 | Online booking account | [Online Booking Account](https://support.boulevard.io/en/articles/6950782-online-booking-account) · 2026-06-05 | Older password guidance conflicts with newer OTP material; use gap register. |
| BL-11.05 | Client self-service portal | [Client Portal](https://support.boulevard.io/en/articles/8648439-client-portal) · 2026-09-28 | Profile, appointments, forms and membership management; clinical shared-profile restrictions apply. |
| BL-11.06 | Booking links to items/categories | [Self-Booking: Link to Specific Items or Categories](https://support.boulevard.io/en/articles/5941527-self-booking-link-to-specific-items-or-categories) · 2025-01-09 | Targeted links are not a separate booking implementation. |
| BL-11.07 | Online gratuity settings | [Gratuity Settings](https://support.boulevard.io/en/articles/5941528-gratuity-settings) · 2026-01-12 | Business-wide policy; clinical suitability remains undecided. |
| BL-11.08 | Booking accessibility | [ADA Compliance](https://support.boulevard.io/en/articles/6417374-ada-compliance) · 2025-06-04 | Vendor accessibility documentation, not verification of our product. |
| BL-11.09 | Enable booking by staff/service | [Enabling and Disabling Online Booking](https://support.boulevard.io/en/articles/5941347-enabling-and-disabling-online-booking) · 2025-07-18 | Visibility and eligibility are controlled separately. |
| BL-11.10 | Share booking links | [Sharing Your Booking Link](https://support.boulevard.io/en/articles/5941534-sharing-your-booking-link) · 2024-07-18 | Distribution through website and other channels. |

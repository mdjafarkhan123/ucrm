# Boulevard inventory — Clinical care, engagement and reporting

**Accessed:** 2026-10-05. **Status:** Public-source inventory, not an approved product specification.

Read the [inventory guide](boulevard-feature-landscape-2026-10-05.md) for coverage, confidence, release status and gaps. Each row has its own primary source and the source-reported update date. An update date is not a feature launch date. Feature existence is confirmed by public documentation; detailed parity and our implementation remain unverified.

All rows: **release Unassigned; delivery Needs research**. Multi-location capabilities remain later under the already agreed scope. Most operational features are shared across appointment businesses; clinical entries require clinical configuration, and explicit beauty, enterprise, hardware and partner restrictions are noted. This relevance classification does not assert identical entitlements across every plan.


## BL-08

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-08.01 | Client forms versus internal charts | [Forms and Charts: Building Forms and Charts](https://support.boulevard.io/en/articles/6989798-forms-and-charts-building-forms-and-charts) · 2026-09-29 | Forms collect client answers; charts are staff-only. Forms/chart entitlement required. |
| BL-08.02 | Reusable template builder | [Forms and Charts: Building Forms and Charts](https://support.boulevard.io/en/articles/6989798-forms-and-charts-building-forms-and-charts) · 2026-09-29 | Input choices, dates, signatures, photos and required fields; service/location triggers. |
| BL-08.03 | Once-only, repeating and expiring forms | [Forms and Charts: Building Forms and Charts](https://support.boulevard.io/en/articles/6989798-forms-and-charts-building-forms-and-charts) · 2026-09-29 | Expiration applies to once-only client forms; do not assume chart expiry. |
| BL-08.04 | Connected profile fields | [Forms and Charts: Connected Fields](https://support.boulevard.io/en/articles/8258319-forms-and-charts-connected-fields) · 2026-10-01 | Moves selected answers into profile fields; medication notes are not structured prescribing records. |
| BL-08.05 | Photo capture and upload | [Forms and Charts: Photo Upload](https://support.boulevard.io/en/articles/8461332-forms-and-charts-photo-upload) · 2025-09-18 | Uses uploaded or device-captured images. |
| BL-08.06 | Image drawing and treatment pins | [Forms and Charts: Photo Markup](https://support.boulevard.io/en/articles/8496145-forms-and-charts-photo-markup) · 2025-09-18 | Advanced charting; distinguish treatment annotations from stock usage. |
| BL-08.07 | Draft, submit and archive documents | [Forms: Submitting, Printing, Saving, Sending, and Deleting](https://support.boulevard.io/en/articles/5941366-forms-submitting-printing-saving-sending-and-deleting) · 2026-09-28 | Submission locks content; archive differs from deletion. No bulk document download described. |
| BL-08.08 | Document notes and corrections | [Forms: Add Notes to Forms](https://support.boulevard.io/en/articles/6326021-forms-add-notes-to-forms) · 2025-07-30 | Notes supplement an existing record; not silent rewriting of signed content. |
| BL-08.09 | Previous-chart copying | [Forms and Charts: Copy Previous Chart](https://support.boulevard.io/en/articles/11157720-forms-and-charts-copy-previous-chart) · 2025-09-18 | Reuse prior answers, with signature/date exclusions and template controls. |
| BL-08.10 | Forms in the client profile | [Forms and Charts in the Client Profile](https://support.boulevard.io/en/articles/7971799-forms-and-charts-in-the-client-profile) · 2025-09-18 | Access across visits, subject to document permissions. |
| BL-08.11 | Resend outstanding forms | [Forms: Submitting, Printing, Saving, Sending, and Deleting](https://support.boulevard.io/en/articles/5941366-forms-submitting-printing-saving-sending-and-deleting) · 2026-09-28 | Appointment-linked reminders; respect transactional opt-outs. |
| BL-08.12 | Clinical workflow workarounds | [Forms & Charts: Best Practices](https://support.boulevard.io/en/articles/15118687-forms-charts-best-practices) · 2026-05-22 | Treatment quotes, invoices and superbills are documented manual workarounds; see competitor gaps. |

## BL-09

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-09.01 | Two-way SMS inbox | [Messages](https://support.boulevard.io/en/articles/5941436-messages) · 2026-07-28 | Business number, shared history, close/unread states, Away replies and permissions. |
| BL-09.02 | Dedicated messaging number | [Messages: Phone Number Set Up](https://support.boulevard.io/en/articles/7217020-messages-phone-number-set-up) · 2025-12-08 | Per-location setup; forwarding/porting options need verification for our providers. |
| BL-09.03 | Business texting registration | [TCR & Creating a Business Phone Number](https://support.boulevard.io/en/articles/8296041-tcr-creating-a-business-phone-number) · 2025-09-18 | Registration is an activation dependency, not just a UI setting. |
| BL-09.04 | Caller identification | [Caller ID](https://support.boulevard.io/en/articles/5941354-caller-id) · 2026-03-12 | Identifies incoming callers against client records. |
| BL-09.05 | Reusable text phrases | [Phrases](https://support.boulevard.io/en/articles/11699500-phrases) · 2026-08-31 | Shared snippets, also used in notes/forms where supported. |
| BL-09.06 | Messaging errors | [Message Delivery Errors](https://support.boulevard.io/en/articles/9341002-message-delivery-errors) · 2026-03-06 | Expose failed delivery; do not treat queued text as delivered. |

## BL-12

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-12.01 | One-time text campaigns | [Text Blasts: Campaign Setup](https://support.boulevard.io/en/articles/9232437-text-blasts-campaign-setup) · 2026-07-14 | Audience, content and timing; dedicated number and marketing consent required. |
| BL-12.02 | Campaign images and GIFs | [Text Blasts: Image & GIF Best Practices](https://support.boulevard.io/en/articles/9861346-text-blasts-image-gif-best-practices) · 2026-03-12 | MMS format and usage restrictions apply. |
| BL-12.03 | One-time email campaigns | [Email Blasts: Campaign Setup](https://support.boulevard.io/en/articles/10088521-email-blasts-campaign-setup) · 2026-07-14 | Distinct from transactional emails and automated campaigns. |
| BL-12.04 | Email template editing | [Email Blasts: Edit a Template](https://support.boulevard.io/en/articles/10088699-email-blasts-edit-a-template) · 2026-06-17 | Brand/content customization; AI additions separately cataloged. |
| BL-12.05 | Audience segmentation | [Text & Email Blasts: Creating an Audience](https://support.boulevard.io/en/articles/10087732-text-email-blasts-creating-an-audience) · 2026-07-14 | Client and purchase/activity filters; location rules restrict access. |
| BL-12.06 | Five preset automated campaigns | [Automated Campaigns: Overview & Setup](https://support.boulevard.io/en/articles/10068551-automated-campaigns-overview-setup) · 2026-03-13 | Slow days, last-minute gaps, rebooking, inactive clients and birthdays; not proof of a general workflow builder. |
| BL-12.07 | Text campaign performance | [Text Blasts: Reporting](https://support.boulevard.io/en/articles/10087828-text-blasts-reporting) · 2025-10-21 | Delivery/engagement and conversion reporting; definitions need P2. |
| BL-12.08 | Email campaign performance | [Email Blasts: Reporting](https://support.boulevard.io/en/articles/10088718-email-blasts-reporting) · 2026-02-11 | Attribution is vendor-defined rather than proven incremental revenue. |
| BL-12.09 | Automated campaign reporting | [Automated Campaigns: Reporting](https://support.boulevard.io/en/articles/10089813-automated-campaigns-reporting) · 2025-09-18 | Performance and attributed charges need reconciliation. |
| BL-12.10 | Marketing opt-in preferences | [Marketing Opt-In Preferences](https://support.boulevard.io/en/articles/6592791-marketing-opt-in-preferences) · 2025-07-07 | Channel-specific choices, distinct from appointment notices. |
| BL-12.11 | Import marketing consent | [Marketing Consent Import](https://support.boulevard.io/en/articles/9892885-marketing-consent-import) · 2025-09-18 | Imported contact details alone are not consent. |
| BL-12.12 | Location-scoped campaign access | [Blast campaign settings for multi-location businesses: Overview & Setup](https://support.boulevard.io/en/articles/15811613-blast-campaign-settings-for-multi-location-businesses-overview-setup) · 2026-07-15 | Audience scope and dynamic primary location affect sends. |
| BL-12.13 | Messaging usage and charges | [Text and Marketing Usage Rates](https://support.boulevard.io/en/articles/7042507-text-and-marketing-usage-rates) · 2026-07-07 | Inbound/outbound segments and campaign billing; do not assume one SMS equals one segment. |

## BL-13

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-13.01 | Business summary dashboard | [Business Summary Dashboard](https://support.boulevard.io/en/articles/15521626-business-summary-dashboard) · 2026-09-11 | New reporting rollout; consolidated operating indicators. |
| BL-13.02 | Sales summary dashboard | [Sales Summary Dashboard](https://support.boulevard.io/en/articles/15591207-sales-summary-dashboard) · 2026-09-25 | New reporting rollout; sales is not identical to bank payouts. |
| BL-13.03 | Report grouping, filtering and columns | [Customizing and Filtering Reports](https://support.boulevard.io/en/articles/15609392-customizing-and-filtering-reports) · 2026-09-08 | Customize analysis; report-specific meanings remain separate. |
| BL-13.04 | Saved report views | [Views](https://support.boulevard.io/en/articles/16515304-views) · 2026-09-09 | Replaces separate custom report copies in the new experience. |
| BL-13.05 | Reporting access and export permissions | [Reporting Permissions](https://support.boulevard.io/en/articles/15609508-reporting-permissions) · 2026-09-30 | Category, self/everyone and assigned-location scope. |
| BL-13.06 | CSV, Excel, PDF and image exports | [Exporting & Backing Up Your Data from Boulevard](https://support.boulevard.io/en/articles/17176434-exporting-backing-up-your-data-from-boulevard) · 2026-09-25 | Tabular exports include all columns; PDF/image capture visible columns. |
| BL-13.07 | Detailed report library | [Detailed Reports](https://support.boulevard.io/en/articles/15609033-detailed-reports) · 2026-09-23 | Every named current report has an individual source entry in the source register. |
| BL-13.08 | Metric definitions | [Reports Data Glossary](https://support.boulevard.io/en/articles/5941389-reports-data-glossary) · 2025-11-25 | Definitions belong to the reporting version; no automatic old/new equivalence. |
| BL-13.R14464567 | Product Inventory Activity Report | [Product Inventory Activity Report](https://support.boulevard.io/en/articles/14464567-product-inventory-activity-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R14465409 | Location Records Report | [Location Records Report](https://support.boulevard.io/en/articles/14465409-location-records-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R14465422 | Disputes Summary Report | [Disputes Summary Report](https://support.boulevard.io/en/articles/14465422-disputes-summary-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R14488927 | Product Records Report | [Product Records Report](https://support.boulevard.io/en/articles/14488927-product-records-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15505800 | Time Card Entries Report | [Time Card Entries Report](https://support.boulevard.io/en/articles/15505800-time-card-entries-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15507056 | Service Records Report | [Service Records Report](https://support.boulevard.io/en/articles/15507056-service-records-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15590288 | Time Block Entries Report | [Time Block Entries Report](https://support.boulevard.io/en/articles/15590288-time-block-entries-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591028 | Appointment Line Items Report | [Appointment Line Items Report](https://support.boulevard.io/en/articles/15591028-appointment-line-items-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591055 | Appointments Report | [Appointments Report](https://support.boulevard.io/en/articles/15591055-appointments-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591062 | Product Inventory On-Hand Report | [Product Inventory On-Hand Report](https://support.boulevard.io/en/articles/15591062-product-inventory-on-hand-report) · 2026-09-23 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591077 | Client Memberships Report | [Client Memberships Report](https://support.boulevard.io/en/articles/15591077-client-memberships-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591080 | Client Records Report | [Client Records Report](https://support.boulevard.io/en/articles/15591080-client-records-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591086 | Client Sales Report | [Client Sales Report](https://support.boulevard.io/en/articles/15591086-client-sales-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591092 | Voucher Balance Report | [Voucher Balance Report](https://support.boulevard.io/en/articles/15591092-voucher-balance-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591104 | Daily Summary Report | [Daily Summary Report](https://support.boulevard.io/en/articles/15591104-daily-summary-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591109 | Gift Card Activity Report | [Gift Card Activity Report](https://support.boulevard.io/en/articles/15591109-gift-card-activity-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591112 | Order Line Items Report | [Order Line Items Report](https://support.boulevard.io/en/articles/15591112-order-line-items-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591116 | Order Payments Report | [Order Payments Report](https://support.boulevard.io/en/articles/15591116-order-payments-report) · 2026-09-25 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591120 | Retail Sales Report | [Retail Sales Report](https://support.boulevard.io/en/articles/15591120-retail-sales-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591123 | Service Sales Report | [Service Sales Report](https://support.boulevard.io/en/articles/15591123-service-sales-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591129 | Voucher Activity Report | [Voucher Activity Report](https://support.boulevard.io/en/articles/15591129-voucher-activity-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591133 | Campaign Performance Report | [Campaign Performance Report](https://support.boulevard.io/en/articles/15591133-campaign-performance-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591140 | Commission Line Items Report | [Commission Line Items Report](https://support.boulevard.io/en/articles/15591140-commission-line-items-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591145 | Commission Summary Report | [Commission Summary Report](https://support.boulevard.io/en/articles/15591145-commission-summary-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591149 | Staff Records Report | [Staff Records Report](https://support.boulevard.io/en/articles/15591149-staff-records-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15591178 | Staff Performance Report | [Staff Performance Report](https://support.boulevard.io/en/articles/15591178-staff-performance-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15601602 | Account Credit Balance Report | [Account Credit Balance Report](https://support.boulevard.io/en/articles/15601602-account-credit-balance-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15601609 | Gift Card Balance Report | [Gift Card Balance Report](https://support.boulevard.io/en/articles/15601609-gift-card-balance-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15901054 | Client Loyalty Activity Report | [Client Loyalty Activity Report](https://support.boulevard.io/en/articles/15901054-client-loyalty-activity-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R15901057 | Memberships Past Due Report | [Memberships Past Due Report](https://support.boulevard.io/en/articles/15901057-memberships-past-due-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16237738 | Disputes Activity Report | [Disputes Activity Report](https://support.boulevard.io/en/articles/16237738-disputes-activity-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16237972 | Membership Records Report | [Membership Records Report](https://support.boulevard.io/en/articles/16237972-membership-records-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16238689 | Client Ratings Report | [Client Ratings Report](https://support.boulevard.io/en/articles/16238689-client-ratings-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16239398 | Membership Cancellations Report | [Membership Cancellations Report](https://support.boulevard.io/en/articles/16239398-membership-cancellations-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16239705 | Register Closeout Entries Report | [Register Closeout Entries Report](https://support.boulevard.io/en/articles/16239705-register-closeout-entries-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16257617 | Membership Sales Report | [Membership Sales Report](https://support.boulevard.io/en/articles/16257617-membership-sales-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16258137 | Package Sales Report | [Package Sales Report](https://support.boulevard.io/en/articles/16258137-package-sales-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16298747 | Client Waitlist Report | [Client Waitlist Report](https://support.boulevard.io/en/articles/16298747-client-waitlist-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16301220 | Referral Performance Report | [Referral Performance Report](https://support.boulevard.io/en/articles/16301220-referral-performance-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16359740 | Client Referrals Report | [Client Referrals Report](https://support.boulevard.io/en/articles/16359740-client-referrals-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16500386 | Supplier Sales Report | [Supplier Sales Report](https://support.boulevard.io/en/articles/16500386-supplier-sales-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16500395 | Voucher Summary Report | [Voucher Summary Report](https://support.boulevard.io/en/articles/16500395-voucher-summary-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16500400 | Staff Retail Sales Report | [Staff Retail Sales Report](https://support.boulevard.io/en/articles/16500400-staff-retail-sales-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16500404 | Staff Service Sales Report | [Staff Service Sales Report](https://support.boulevard.io/en/articles/16500404-staff-service-sales-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16515949 | Client Retention Report | [Client Retention Report](https://support.boulevard.io/en/articles/16515949-client-retention-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16516003 | Membership Event Summary Report | [Membership Event Summary Report](https://support.boulevard.io/en/articles/16516003-membership-event-summary-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16516021 | Account Credit Activity Report | [Account Credit Activity Report](https://support.boulevard.io/en/articles/16516021-account-credit-activity-report) · 2026-09-03 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16516060 | Order Line Item Discounts Report | [Order Line Item Discounts Report](https://support.boulevard.io/en/articles/16516060-order-line-item-discounts-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16516102 | Operator Sales Report | [Operator Sales Report](https://support.boulevard.io/en/articles/16516102-operator-sales-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16516113 | Schedule Detail Report | [Schedule Detail Report](https://support.boulevard.io/en/articles/16516113-schedule-detail-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16516116 | Schedule Entries Report | [Schedule Entries Report](https://support.boulevard.io/en/articles/16516116-schedule-entries-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16516124 | Staff Attendance Summary Report | [Staff Attendance Summary Report](https://support.boulevard.io/en/articles/16516124-staff-attendance-summary-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |
| BL-13.R16516128 | Staff Client Retention Report | [Staff Client Retention Report](https://support.boulevard.io/en/articles/16516128-staff-client-retention-report) · 2026-08-31 | Individual report; staged rollout. Field definitions and caveats remain P2 work. |

## BL-14

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-14.01 | Prescriber and assistant setup | [Getting started with ePrescribe](https://support.boulevard.io/en/articles/13773728-getting-started-with-eprescribe) · 2026-09-01 | Clinical package, separate provider integration and identity proofing. |
| BL-14.02 | Location and staff prescribing access | [Manage ePrescribe Locations & Staff](https://support.boulevard.io/en/articles/14152005-manage-eprescribe-locations-staff) · 2026-06-15 | Each location is a separate ScriptSure practice. |
| BL-14.03 | Create and manage prescriptions | [Manage Patient Prescriptions in ePrescribe](https://support.boulevard.io/en/articles/14152011-manage-patient-prescriptions-in-eprescribe) · 2026-09-01 | ScriptSure integration; controlled/noncontrolled/compound support is conditional on credentials/network. |
| BL-14.04 | Medication/allergy reconciliation | [ePrescribe: Tracking client medication and allergies](https://support.boulevard.io/en/articles/14489548-eprescribe-tracking-client-medication-and-allergies) · 2026-04-08 | Free-text intake notes do not automatically become structured interaction-check data. |
| BL-14.05 | Prescribing migration | [ePrescribe ScriptSure Migration](https://support.boulevard.io/en/articles/15197785-eprescribe-scriptsure-migration) · 2026-07-02 | Separate migration process; no assumption all historical clinical data migrates. |
| BL-14.06 | Prescriber subscription | [ePrescribe pricing](https://support.boulevard.io/en/articles/13773754-eprescribe-pricing) · 2026-09-23 | Per prescriber monthly fee plus annual identity-proofing fee; assistants included; no monthly proration. |
| BL-14.07 | Prescription integration limits | [ePrescribe FAQs](https://support.boulevard.io/en/articles/14556542-eprescribe-faqs) · 2026-09-01 | No wholesale practice-stock ordering; no direct ScriptSure access if Boulevard is down; see source for location merge caveats. |

## BL-15

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-15.01 | Supervisor review queue | [Sign Off on Completed Forms and Charts](https://support.boulevard.io/en/articles/8681202-sign-off-on-completed-forms-and-charts) · 2026-08-06 | Review across pending documents; advanced charting and reviewer access required. |
| BL-15.02 | Bulk approval and completion without review | [Sign Off on Completed Forms and Charts](https://support.boulevard.io/en/articles/8681202-sign-off-on-completed-forms-and-charts) · 2026-08-06 | Different privileged actions; not approval for our clinical policy. |
| BL-15.03 | Reusable/drawn reviewer signatures | [New: What's changing with Sign-off?](https://support.boulevard.io/en/articles/15715237-new-what-s-changing-with-sign-off) · 2026-07-28 | Signature options and review changes; reconcile older instructions. |

## BL-16

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-16.01 | Audit access and historical coverage | [Audit Log FAQ](https://support.boulevard.io/en/articles/15061025-audit-log-faq) · 2026-05-11 | Business-wide default; event tracking starts January or May 2026 depending on event. |

## BL-17

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-17.01 | AI receptionist call handling | [AI Receptionist Overview](https://support.boulevard.io/en/articles/16105086-ai-receptionist-overview) · 2026-09-17 | Beta; sends booking/portal links rather than booking directly by voice. |
| BL-17.02 | Receptionist routing and clinical handoff | [AI Receptionist — Setting Up AI Receptionist](https://support.boulevard.io/en/articles/16105111-ai-receptionist-setting-up-ai-receptionist) · 2026-09-28 | Hours, transfer/message, emergency disclaimer and medical-director routing; avoid call loops. |
| BL-17.03 | AI call log and transcripts | [AI Receptionist — Frequently Asked Questions](https://support.boulevard.io/en/articles/16105159-ai-receptionist-frequently-asked-questions) · 2026-09-28 | Inbox history, call outcomes and caller matching; identity edge cases remain unverified. |
| BL-17.04 | Pause AI receptionist | [Pausing AI Receptionist](https://support.boulevard.io/en/articles/16192728-pausing-ai-receptionist) · 2026-08-07 | Pausing also needs a forwarding destination decision. |
| BL-17.05 | AI usage and billing | [AI Receptionist Beta Pricing](https://support.boulevard.io/en/articles/16102622-ai-receptionist-beta-pricing) · 2026-09-17 | Free through November 2026; then location/minute/text usage. Future terms can change. |

## BL-18

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-18.01 | Client financing at checkout | [Using Buy Now, Pay Later at Checkout](https://support.boulevard.io/en/articles/15773352-using-buy-now-pay-later-at-checkout) · 2026-08-04 | Affirm/Klarna; excluded for memberships, booking-flow payment and custom booking; requires current Duo software. |
| BL-18.02 | Financing enablement and minimum order | [Admin guide: Buy Now, Pay Later](https://support.boulevard.io/en/articles/15465272-admin-guide-buy-now-pay-later) · 2026-08-11 | Provider eligibility and merchant terms apply; not a lending service we can simply copy. |
| BL-18.03 | Financing awareness during booking | [How to market Buy Now, Pay Later at your business](https://support.boulevard.io/en/articles/16302041-how-to-market-buy-now-pay-later-at-your-business) · 2026-08-11 | Eligibility links/promotional placement do not mean online BNPL payment is supported. |

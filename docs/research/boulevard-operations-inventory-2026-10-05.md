# Boulevard inventory — Integrations, apps, payments and setup

**Accessed:** 2026-10-05. **Status:** Public-source inventory, not an approved product specification.

Read the [inventory guide](boulevard-feature-landscape-2026-10-05.md) for coverage, confidence, release status and gaps. Each row has its own primary source and the source-reported update date. An update date is not a feature launch date. Feature existence is confirmed by public documentation; detailed parity and our implementation remain unverified.

All rows: **release Unassigned; delivery Needs research**. Multi-location capabilities remain later under the already agreed scope. Most operational features are shared across appointment businesses; clinical entries require clinical configuration, and explicit beauty, enterprise, hardware and partner restrictions are noted. This relevance classification does not assert identical entitlements across every plan.


## BL-19

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-19.01 | Apple/Google/personal calendar sync | [Personal Calendar Syncing](https://support.boulevard.io/en/articles/5941554-personal-calendar-syncing) · 2026-05-22 | Two-way feeds; two-month window, delayed refresh, edit at origin, recurring imported events unsupported. |
| BL-19.02 | Facebook and Instagram booking buttons | [Facebook & Instagram Book Now App](https://support.boulevard.io/en/articles/5941546-facebook-instagram-book-now-app) · 2025-12-03 | Business accounts; opens standard overlay even with a custom API booking experience. |
| BL-19.03 | Google Business booking link | [Reserve with Google Integration](https://support.boulevard.io/en/articles/6790178-reserve-with-google-integration) · 2025-04-10 | Requires an existing matching Google Business Profile; opens Boulevard booking. |
| BL-19.04 | Shopify inventory sync | [Shopify Integration](https://support.boulevard.io/en/articles/5941544-shopify-integration) · 2026-09-10 | Mapped locations and matching products; quantity sync is bidirectional. |
| BL-19.05 | Shopify gift-card sync | [Shopify Integration](https://support.boulevard.io/en/articles/5941544-shopify-integration) · 2026-09-10 | Requires Shopify Plus; verify balance/refund edge cases before reuse. |
| BL-19.06 | QuickBooks nightly export | [QuickBooks Online Integration Setup](https://support.boulevard.io/en/articles/6793204-quickbooks-online-integration-setup) · 2025-09-18 | Paid add-on; one QuickBooks company; limited suitability for prepaid usage units; all locations billed. |
| BL-19.07 | Hotel room charges | [OPERA Integration](https://support.boulevard.io/en/articles/6156460-opera-integration) · 2025-06-04 | Post full/partial bills to OPERA; refunds/voids sync; partner setup required. |
| BL-19.08 | Sustainability fees | [Green Circle Salons App](https://support.boulevard.io/en/articles/5941548-green-circle-salons-app) · 2026-10-01 | Salon-oriented fee configuration; partner program rather than clinical functionality. |
| BL-19.09 | Color measurement integration | [Vish x Boulevard](https://support.boulevard.io/en/articles/7880772-vish-x-boulevard) · 2025-09-18 | Beauty-specific scale/software; onboarding with both vendors required. |
| BL-19.10 | Zapier workflows | [Zapier Integration](https://support.boulevard.io/en/articles/5941545-zapier-integration) · 2023-08-08 | Supported triggers/actions determine scope; not arbitrary access to every product action. |
| BL-19.11 | Public/custom app installation | [Connect Custom and Public Apps to Boulevard](https://support.boulevard.io/en/articles/6265963-connect-custom-and-public-apps-to-boulevard) · 2025-06-17 | Older entitlement wording conflicts with newer Enterprise-only custom-app documentation. |
| BL-19.12 | Meta advertising conversion tracking | [Event Tracking: Meta Pixel](https://support.boulevard.io/en/articles/11326887-event-tracking-meta-pixel) · 2026-09-23 | Business-level pixel; excluded from Essentials in source. Clinical data suitability unresolved. |
| BL-19.13 | GA4 booking event tracking | [Event Tracking: Google Analytics (GA4)](https://support.boulevard.io/en/articles/11326791-event-tracking-google-analytics-ga4) · 2026-09-23 | Location dimensions are prospective; requires correct analytics setup. |

## BL-20

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-20.01 | Register custom apps and scopes | [Creating and Registering Your App with Boulevard](https://support.boulevard.io/en/articles/17182228-creating-and-registering-your-app-with-boulevard) · 2026-09-25 | Enterprise-only custom apps; machine-to-machine or OAuth installation; scoped access and optional webhooks. |
| BL-20.02 | Developer support requests | [API Requests: Developer Support Portal](https://support.boulevard.io/en/articles/6577513-api-requests-developer-support-portal) · 2025-06-17 | Enterprise customer support, not an end-user application feature. |
| BL-20.03 | Hourly warehouse data share | [Snowflake Data Share](https://support.boulevard.io/en/articles/11498228-snowflake-data-share) · 2025-10-07 | Qualifying Enterprise account plus own Snowflake/analytics capability. |

## BL-21

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-21.01 | Professional mobile app | [Professional App](https://support.boulevard.io/en/articles/9180930-professional-app) · 2026-07-28 | iOS/Android companion; access permission; does not replace the web dashboard. |
| BL-21.02 | Mobile booking and visit management | [What’s New with the Professional App Booking Experience](https://support.boulevard.io/en/articles/10222218-what-s-new-with-the-professional-app-booking-experience) · 2025-12-04 | Mobile scheduling improvements; check surface-specific limitations. |
| BL-21.03 | Mobile checkout | [Professional App Checkout](https://support.boulevard.io/en/articles/5941513-professional-app-checkout) · 2025-07-07 | No mobile-only voucher redemption, loyalty, group/retail-only orders or order management; web-prepared checkout can carry forward. |
| BL-21.04 | Mobile forms and charts | [Forms and Charts in the Professional App](https://support.boulevard.io/en/articles/8038055-forms-and-charts-in-the-professional-app) · 2026-06-10 | Permissions and clinical entitlements still apply. |
| BL-21.05 | Mobile staff performance | [Staff Performance in the Professional App](https://support.boulevard.io/en/articles/5941514-staff-performance-in-the-professional-app) · 2025-07-07 | Staff metrics, not the entire reporting suite. |
| BL-21.06 | Duo customer-facing terminal | [Boulevard Duo: Introduction](https://support.boulevard.io/en/articles/5941542-boulevard-duo-introduction) · 2025-09-02 | iPad plus supported reader for card-present collection; iPad Mini excluded in guide. |
| BL-21.07 | Duo without a card reader | [Boulevard Duo: Setting Up a Duo App without a Duo Card Reader](https://support.boulevard.io/en/articles/7910602-boulevard-duo-setting-up-a-duo-app-without-a-duo-card-reader) · 2025-11-03 | App-only use exists; do not conflate check-in hardware with payment hardware. |
| BL-21.08 | Duo check-in and walk-ins | [Boulevard Duo App: Check-In, Walk-In, Forms](https://support.boulevard.io/en/articles/7910484-boulevard-duo-app-check-in-walk-in-forms) · 2025-09-18 | Arrival notification, front-desk queue and entitled client form completion. |
| BL-21.09 | Duo card checkout | [Boulevard Duo: Checkout](https://support.boulevard.io/en/articles/7913586-boulevard-duo-checkout) · 2026-07-28 | Reader/app workflow distinct from web and Professional App checkout. |
| BL-21.10 | Customer gratuity on Duo | [Boulevard Duo App: Collect Gratuity](https://support.boulevard.io/en/articles/7913613-boulevard-duo-app-collect-gratuity) · 2026-04-09 | Customer-facing tipping surface. |
| BL-21.11 | Duo gift cards | [Boulevard Duo: Gift Card Functionality](https://support.boulevard.io/en/articles/6523363-boulevard-duo-gift-card-functionality) · 2026-07-07 | Physical gift-card workflow, separate from generic card payments. |
| BL-21.12 | Duo software and firmware maintenance | [Boulevard Duo: Updating Firmware & Configuration](https://support.boulevard.io/en/articles/8550350-boulevard-duo-updating-firmware-configuration) · 2025-06-04 | Hardware/software dependency, not a new business feature. |
| BL-21.13 | Staff two-step verification | [Two-step verification: Admin setup](https://support.boulevard.io/en/articles/11826313-two-step-verification-admin-setup) · 2026-09-04 | Per-staff rollout and international-number documentation conflict; see source reconciliation. |
| BL-21.14 | Inactivity and maximum sessions | [Session duration and automatic logout](https://support.boulevard.io/en/articles/9347071-session-duration-and-automatic-logout) · 2026-09-01 | Nightly Dashboard and weekly Professional App logout; Duo exempt from scheduled logout. |
| BL-21.15 | Network access restrictions | [IP Restriction and Approved Network Ranges](https://support.boulevard.io/en/articles/5941358-ip-restriction-and-approved-network-ranges) · 2026-06-10 | Configurable allowed networks; not a replacement for role permissions. |
| BL-21.16 | Clinical privacy configuration | [Protected Health Information (PHI) Security Requirements](https://support.boulevard.io/en/articles/8550292-protected-health-information-phi-security-requirements) · 2026-03-03 | BAA, access, logout and portal configuration; vendor claim does not establish our compliance. |
| BL-21.17 | Staff login and password recovery | [Logging into Boulevard](https://support.boulevard.io/en/articles/16776825-logging-into-boulevard) · 2026-09-03 | Staff authentication is distinct from client portal login. |
| BL-21.18 | Payment and peripheral compatibility | [Hardware Recommendations & Testing](https://support.boulevard.io/en/articles/6047189-hardware-recommendations-testing) · 2026-01-27 | Device requirements and scanner/printer compatibility must be checked per surface. |

## BL-22

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-22.01 | Merchant application and verification | [Submitting Merchant Details](https://support.boulevard.io/en/articles/5941325-submitting-merchant-details) · 2026-08-15 | Underwriting, identity and bank details; location-specific accounts; HSA/FSA attestation where eligible. |
| BL-22.02 | Bank account linking | [Linking a Bank Account](https://support.boulevard.io/en/articles/11036642-linking-a-bank-account) · 2026-04-16 | Checking-account payout configuration with protected access. |
| BL-22.03 | Multi-merchant split settlements | [Multi-Merchant Accounts](https://support.boulevard.io/en/articles/5941324-multi-merchant-accounts) · 2026-10-04 | One checkout can route independent merchant shares; additional fees and wallet restrictions. |
| BL-22.04 | Payment activity and reconciliation | [Payment Processing Overview](https://support.boulevard.io/en/articles/6128829-payment-processing-overview) · 2026-09-25 | Transactions, payouts and fees; excludes money collected outside the processor. |
| BL-22.05 | Standard and instant payouts | [Payouts, Fees, and Merchant Activity](https://support.boulevard.io/en/articles/5941482-payouts-fees-and-merchant-activity) · 2026-09-29 | Instant availability depends on eligible bank/network and funds. |
| BL-22.06 | Reconcile net bank deposits | [Understanding Payout Reconciliation Reporting](https://support.boulevard.io/en/articles/16951468-understanding-payout-reconciliation-reporting) · 2026-10-01 | Fees/refunds/adjustments explain why gross sales differ from deposits. |
| BL-22.07 | Merchant tax documents | [Merchant Accounts: 1099-K and Tax FAQ](https://support.boulevard.io/en/articles/8780711-merchant-accounts-1099-k-and-tax-faq) · 2026-02-16 | Vendor document access/support; do not adopt article thresholds as current legal advice. |
| BL-22.08 | Card address verification | [Address Verification Services (AVS) & BLVD](https://support.boulevard.io/en/articles/6472139-address-verification-services-avs-blvd) · 2026-03-05 | Card verification and cancellation-fee collection can fail. |
| BL-22.09 | Credit-card surcharge program | [Boulevard Offset](https://support.boulevard.io/en/articles/7235793-boulevard-offset) · 2026-10-04 | Credit only, not debit; disclosures/eligibility; no per-sale waiver in documented flow. |
| BL-22.10 | Dispute notifications and tracking | [Chargebacks and Disputes Overview](https://support.boulevard.io/en/articles/7885416-chargebacks-and-disputes-overview) · 2025-09-18 | Merchant risk workflow separate from customer refunds. |
| BL-22.11 | Submit dispute evidence | [Responding to Disputes](https://support.boulevard.io/en/articles/9010604-responding-to-disputes) · 2026-05-07 | Deadlines, required evidence and decisions; winning is not guaranteed. |
| BL-22.12 | Dispute escalation | [Arbitration in Dispute Cases](https://support.boulevard.io/en/articles/9267205-arbitration-in-dispute-cases) · 2025-09-18 | Provider/network process, not an ordinary app status transition. |
| BL-22.13 | Business capital offers | [Boulevard Capital FAQ](https://support.boulevard.io/en/articles/8959042-boulevard-capital-faq) · 2026-09-30 | Invitation-based Pipe merchant advance; separate from client BNPL. |
| BL-22.14 | Subscription billing and invoices | [Understanding Your Boulevard Bill](https://support.boulevard.io/en/articles/15521146-understanding-your-boulevard-bill) · 2026-09-23 | Platform billing, not a client's unpaid service invoice. |
| BL-22.15 | Update subscription payment method | [Updating Your Credit Card for Boulevard Billing](https://support.boulevard.io/en/articles/5941323-updating-your-credit-card-for-boulevard-billing) · 2026-08-15 | Protected account administration. |
| BL-22.16 | Clinical add-on | [Medspa Add-On](https://support.boulevard.io/en/articles/9084775-medspa-add-on) · 2026-09-28 | Advanced markup/sign-off, privacy configuration and clinical feature eligibility; differs from ordinary Forms add-on. |

## BL-23

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-23.01 | Multiple locations and franchises | [Multilocation business support](https://support.boulevard.io/en/articles/11682178-multilocation-business-support) · 2026-07-14 | Shared account with location operations; later under agreed launch boundary. |
| BL-23.02 | Location groups, tags and identifiers | [Location Organizer](https://support.boulevard.io/en/articles/12601326-location-organizer) · 2025-10-22 | Enterprise organization/reporting dimensions; not a franchise royalty engine. |
| BL-23.03 | Location-aware permission management | [Granular permission groups](https://support.boulevard.io/en/articles/11662777-granular-permission-groups) · 2026-08-25 | Delegated managers cannot freely change every location's groups. |
| BL-23.04 | Cross-location membership management | [Membership settings](https://support.boulevard.io/en/articles/11101465-membership-settings) · 2025-09-18 | Business-level switch; financial reconciliation is a separate reporting concern. |

## BL-24

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-24.01 | Business branding | [Business Logo and Banner Placement](https://support.boulevard.io/en/articles/6560905-business-logo-and-banner-placement) · 2025-06-04 | Business identity assets across customer-facing surfaces. |
| BL-24.02 | Location opening hours | [Location Hours](https://support.boulevard.io/en/articles/7898267-location-hours) · 2025-09-18 | Used for contact/operation context; staff/resource schedules remain separate. |
| BL-24.03 | Booking installation on existing websites | [Installing the Self-Booking Overlay: WordPress](https://support.boulevard.io/en/articles/5941343-installing-the-self-booking-overlay-wordpress) · 2023-12-14 | Also documented for Wix, Squarespace, Shopify, Square and Weebly in source register. |
| BL-24.04 | Historical file migration | [Historical Client Files: Export and Import Guide](https://support.boulevard.io/en/articles/11584912-historical-client-files-export-and-import-guide) · 2025-10-02 | Guide body points to an attached PDF; detailed format remains a P2 evidence gap. |
| BL-24.05 | Data export and backup | [Exporting & Backing Up Your Data from Boulevard](https://support.boulevard.io/en/articles/17176434-exporting-backing-up-your-data-from-boulevard) · 2026-09-25 | Exportable tables differ between reporting versions; clinical documents have separate limits. |
| BL-24.06 | Staff privacy-rights request | [Staff Account Privacy Rights Request](https://support.boulevard.io/en/articles/8814605-staff-account-privacy-rights-request) · 2025-09-18 | Account-data request process; not proof of full client-record deletion tooling. |
| BL-24.07 | Daily opening and closing guidance | [Daily Opening & Closing Procedures](https://support.boulevard.io/en/articles/5941317-daily-opening-closing-procedures) · 2024-06-24 | Operational checklist connecting calendar, checkout and closeout. |
| BL-24.08 | Keyboard navigation | [Keyboard Shortcuts](https://support.boulevard.io/en/articles/5941333-keyboard-shortcuts) · 2023-07-08 | Usability aid; not a separate workflow domain. |

## BL-25

| Feature ID | Capability / purpose | Primary source · updated | Availability or boundary |
| --- | --- | --- | --- |
| BL-25.01 | Onboarding assistance | [Partnering with your Boulevard Onboarding Specialist](https://support.boulevard.io/en/articles/8797012-partnering-with-your-boulevard-onboarding-specialist) · 2025-09-18 | Vendor service: setup, migration validation and training support. |
| BL-25.02 | Role-based and medspa training | [Navigating Boulevard Academy](https://support.boulevard.io/en/articles/5941590-navigating-boulevard-academy) · 2026-02-11 | Vendor education; deeper lessons supplement help articles. |
| BL-25.03 | On-demand topic sessions | [Boulevard Academy Link & Learn](https://support.boulevard.io/en/articles/8285020-boulevard-academy-link-learn) · 2026-02-11 | Training catalog, not evidence every preview is shipped. |
| BL-25.04 | Support chat | [Help Chat / Customer Support](https://support.boulevard.io/en/articles/10335883-help-chat-customer-support) · 2025-11-25 | Vendor support channel, separate from client messaging. |
| BL-25.05 | Refer businesses to Boulevard | [Boulevard’s Customer Referral Program](https://support.boulevard.io/en/articles/12895499-boulevard-s-customer-referral-program) · 2026-05-11 | Vendor acquisition program, not the client's own referral-reward feature. |
| BL-25.06 | Submit product feedback | [How to Submit a Feature Idea to Boulevard](https://support.boulevard.io/en/articles/5941326-how-to-submit-a-feature-idea-to-boulevard) · 2026-01-28 | Request channel; a requested feature is not proof of availability. |

## Additional official catalog capabilities

These entries are confirmed at catalog level; detailed behavior and account availability remain partly confirmed. Release is Unassigned and delivery Needs research. Sources accessed 2026-10-05.

| Feature ID | Capability / purpose | Primary source | Boundary |
| --- | --- | --- | --- |
| BL-19.90 | Okta single sign-on | [Integration directory](https://www.joinblvd.com/integrations) | Partner integration; entitlement and setup need P2G research. |
| BL-19.91 | REACH.ai appointment marketing | [Integration directory](https://www.joinblvd.com/integrations) | Partner capability, not native Boulevard automation. |
| BL-19.92 | Widewail reputation and video testimonials | [Integration directory](https://www.joinblvd.com/integrations) | Partner capability; review-policy choices remain open. |
| BL-20.90 | Admin API for business operations | [Developer portal](https://developers.joinblvd.com/) | Enterprise availability; no API parity assumed. |
| BL-20.91 | Client API for custom booking experiences | [Developer portal](https://developers.joinblvd.com/) | Enterprise availability; separate from native booking. |
| BL-20.92 | Payment card tokenization | [Developer portal](https://developers.joinblvd.com/) | Developer capability; does not establish our payment compliance. |
| BL-20.93 | Book SDK and booking starter | [Developer portal](https://developers.joinblvd.com/) | Tools for custom booking, not additional consumer features. |
| BL-17.90 | AI-assisted email copy, subjects and images | [Boulevard AI](https://www.joinblvd.com/features/boulevard-ai) | Marketing-page evidence; precise editor controls unverified. |
| BL-17.91 | Billie vendor-support assistant | [Boulevard AI](https://www.joinblvd.com/features/boulevard-ai) | Helps Boulevard customers; separate from Beau client calls. |

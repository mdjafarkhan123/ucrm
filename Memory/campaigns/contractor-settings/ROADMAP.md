# Contractor Settings Roadmap

| Part | Outcome | Status | Dependencies | Packet | Completion gate |
| --- | --- | --- | --- | --- | --- |
| 1 | Settings foundation and Business Profile | Desktop browser-verified 2026-08-24; Jafar accepted the 390px/mobile pass; two readiness/save bugs fixed; blocked open only on the Quotes frozen-branding acceptance test | Confirmed Part 1 contract and reference tours | `parts/01-settings-foundation-and-business-profile.md` | Authorized contractors can use the responsive, permission-aware Settings directory and safely manage one shared business identity, branding, timezone, currency, address, and hours; every affected consumer remains truthful and browser checks pass. |
| 2 | Quotes and pricing settings | Closed 2026-08-24 — 2A Taxes, 2B Price Book, and 2C Quote Settings all closed; permission-denial and target-margin-redaction checks browser-verified in 2C's final pass | 1 and shipped Quotes foundation | `parts/02a-taxes.md`, `parts/02b-price-book-management.md`, `parts/02c-quote-settings.md` | Met: Taxes, Price Book management, default terms, authorizer/signature, and staff-only target margin affect new drafts without rewriting history. |
| 3 | Team and access settings | 3A/3B/3D closed; 3C browser gate passed, Pending-member actions remain; 3E pending; 3F gated by Scheduling | 1 and existing collaboration foundation | `parts/03-team-and-access.md`, `parts/03a-access-and-data-foundation.md`, `parts/03b-invitation-lifecycle.md`, `parts/03c-team-directory-and-member-details.md`, `parts/03d-roles-and-permissions.md` | Administrators can manage members, roles, permissions, and applicable availability without weakening tenant or feature access. |
| 4 | Request and booking forms | Pending | 1, Requests, and Scheduling truth | Create when active | Contractors can manage multiple request/booking forms, defaults, public links, fields, availability, assignment, and honest creation outcomes. |
| 5 | Feature-owned settings integrations | Pending | 1 and each owning domain | Create per dependency-ready slice | Communications, SMS, Jobs, Invoices/Payments, Client Portal, Reputation, Notifications, and Integrations expose only configuration backed by working features. |
| 6 | Automation settings | Pending | Required business events and Communications channels | Create when active | Proven presets are understandable and safe; the custom builder ships only after shared engine guardrails exist. |

## Standing decisions

- The approved product truth is `docs/contractor-settings-blueprint.md`; Memory only routes execution.
- The Settings home is one scrollable page, not nested category menus.
- Seven bordered category sections expose usable destinations directly as icon/name/description cards.
- The sticky category bar scrolls to sections and highlights the visible group; it is not a tab interface.
- Cards use four/three/two/one columns across wide desktop/desktop/tablet/mobile.
- The personal account shortcut sits above business sections.
- Pages and cards are permission-aware; server enforcement matches visibility.
- Feature-owned settings ship with the feature they control. No dead destination is added early.
- Shared branding affects customer surfaces, never the contractor CRM theme.
- Defaults affect new drafts and never silently rewrite historical or customer-visible truth.
- Contractor configuration remains separate from Jafar's Platform Owner infrastructure and limits.
- The confirmed Part 1 refinements live in `docs/contractor-settings-blueprint.md` under **Confirmed Part 1 behavior**; this roadmap does not duplicate them.

## Main risks

- Existing organization identity is split across onboarding, organization rows, and organization settings;
  choosing ownership without an audit could create conflicting sources of truth.
- Changing currency or timezone after work exists can misrepresent historical money and dates unless the
  boundary between defaults and frozen records is explicit.
- Logo storage and customer rendering can leak tenant data or depend on expiring links if treated as a plain
  form field.
- Card visibility without matching server authorization would create cosmetic rather than real permissions.
- Building future cards before their domains exist would recreate the dead-page problem this campaign rejects.

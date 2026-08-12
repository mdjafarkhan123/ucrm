# CRM Build Sequence

> This is a dependency-aware roadmap. Build each feature vertically (`Database → RLS → Logic → Cache → UI → Tests`), while allowing foundation work to be shared by later modules.

## 1. Engineering Foundation

- TypeScript strict
- ESLint + Prettier
- Vitest + Playwright
- Zod
- SCSS
- Bits UI
- TanStack Query
- Supabase client/server setup
- Environment validation
- Error/logging conventions
- Migration conventions

## 2. Design Foundation

**Status: complete**

- Design tokens
- Typography
- Spacing/colors/radius/borders
- Core components only:
  - Button
  - Input
  - Textarea
  - Select
  - Checkbox
  - FormField
  - Badge
  - Card
  - Dialog
  - Dropdown
  - Tabs
  - PageHeader
  - Loading/Empty/Error states
  - Toast
- Contractor AppShell
- `/jafar` AppShell

## 3. Tenancy + Database Foundation

- `organizations`
- `profiles`
- `organization_members`
- roles/permissions
- organization settings/status
- indexes/constraints
- RLS
- tenant-isolation tests

## 4. Authentication

### Contractor

- Supabase Auth
- Login
- Password reset
- Session handling
- Protected app routes
- Resolve user → single membership → org → permissions

### Platform Owner

- Separate `/jafar/login`
- Separate secure session/cookie
- Protected `/jafar/*`
- No contractor `org_id`

## 5. Minimal `/jafar`

- Owner login
- Organization list
- Create organization
- Create first contractor admin
- Organization detail
- Activate/suspend organization

## 6. Data / Cache Architecture

- TanStack Query setup
- Query-key conventions
- SSR hydration
- CSR cached navigation
- Targeted invalidation
- Supabase Realtime for external/cross-user changes

## 7. Core Platform Infrastructure

- Standard domain event catalog
- `activity_events`
- `outbox_events`
- Timeline/activity conventions
- Audit/history conventions
- File and storage foundations
- Attachment metadata and authorization

## 8. Customers + Properties

- Customer schema + RLS
- Properties
- Contacts/emails/phones as required
- Notes/tags
- Customer list
- Search
- Create/edit/archive
- Customer detail
- Property management
- Duplicate warning
- Timeline foundation
- Tests

## 9. Requests + Assessments

- Request schema
- Assessment schema
- Create/view/edit requests
- Customer/property relationship
- Schedule assessment
- Complete assessment
- Timeline/activity
- Prepare future Quote/Job conversion

## 10. Pipeline

- Opportunities
- Pipeline stages
- Stage history
- Lost reasons
- Board + list
- Move stage
- Won/Lost
- Follow-up fields
- Add drag/drop after mutations are proven

## 11. Quotes

- Quotes
- Quote line items
- Totals/tax/discount
- Draft/send
- Public quote page
- View tracking
- Approve/decline/request changes
- Deposit support
- Convert quote → job
- Snapshot-copy line items

## 12. Jobs

- Jobs
- Job line items
- Assignments
- Instructions/notes
- Manual job creation
- Quote → job
- Job detail/history

## 13. Visits + Schedule

- Visits
- Events
- Scheduled / Anytime / Unscheduled
- Day/week/month views
- Assessment + visit calendar
- Complete/reschedule
- Crew assignment
- Add advanced routing later

## 14. Invoices + Payments

- Invoices
- Invoice line items
- Payments
- Partial payments
- Balances
- Draft/send
- Public invoice page
- Due/past-due states
- Manual payments
- Online payments later

## 15. Dashboard

- New requests
- Pipeline summary
- Quotes awaiting response
- Today/upcoming visits
- Active jobs
- Requires invoicing
- Outstanding invoices
- Recent activity

## 16. Unified Inbox

- Conversations
- Messages
- Participants
- Attachments
- Assignment/unread/status
- Start with email + internal notes
- Add web chat
- Later SMS / WhatsApp / Messenger

## 17. Events + Notifications

- `notifications`
- notification preferences
- Separate routine activity from actionable notifications

## 18. Worker Infrastructure

- Redis
- BullMQ
- Separate Node worker
- Queues:
  - events
  - automation
  - communications
  - maintenance
- Retries
- Backoff
- Idempotency
- Dead-letter handling
- Logging

## 19. Automations

- Preset automations first
- Trigger → Conditions → Ordered Actions
- Workflow definitions in Postgres
- Execution history in Postgres
- Delays/retries in BullMQ
- No visual node editor initially

## 20. Customer-Facing Features

- Quote links
- Invoice links
- Booking
- Customer portal
- Receipts
- Appointment visibility

## 21. Reputation + Growth

- Review requests
- Private negative feedback
- Review tracking
- Repeat-service reminders
- Growth Feed

## 22. Complete `/jafar`

- Plans
- Feature flags
- Usage limits
- Twilio/SMS setup
- Email-domain setup
- Integrations
- Web-chat settings
- Dead letters
- Operational monitoring

## 23. Reporting

- Leads/source
- Pipeline conversion
- Quote performance
- Jobs/visits
- Requires invoicing
- Revenue/balances
- Payment speed
- Job profitability
- Reviews/repeat customers

---

# Per-Feature Implementation Process

For every module/task:

1. Research relevant Jobber behavior
2. Read/write our module specification
3. Audit existing code
4. Define data model + lifecycle
5. Create migration
6. Add RLS/security
7. Add Zod validation
8. Add repository/service/business commands
9. Add TanStack Query contract
10. Build demo UI if design is uncertain
11. Build/reuse shared components
12. Implement production UI
13. Add loading/empty/error states
14. Add unit/integration/RLS tests
15. Add critical Playwright flow
16. Run separate agent review
17. Fix approved findings
18. Verify and commit

## Core Rule

Build vertically:

`Database → RLS → Logic → Cache → UI → Tests`

Core infrastructure may be scaffolded early, but each business feature should still be completed vertically. Do not build all database tables first or all UI components first.

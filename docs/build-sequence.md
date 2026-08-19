# CRM Build Sequence

Status: Approved sequencing guide
Updated: 2026-08-15

This document owns the dependency order of major product campaigns. Product documents own behavior,
campaign roadmaps own execution, and code, migrations, and tests own implemented truth.

Build each feature as a vertical slice through its required database, RLS, server logic, cache,
interface, and verification. Create shared foundations only when a dependency-ready feature needs them.

## Current foundation

The following foundations already exist and must be audited rather than rebuilt:

- SvelteKit, TypeScript, SCSS, shared design primitives, and contractor and `/jafar` shells;
- Supabase Auth, organization membership, tenant foundations, roles, and permissions;
- package versions, feature entitlements, limits, and commercial lifecycle controls;
- Platform Owner onboarding, organization management, durable operations, notifications, and history;
- recoverable organization closure, strict purge, and scheduled cleanup;
- early contact, property, and request schemas and APIs that are not yet accepted as complete domains.

The data/cache architecture campaign remains paused and resumes when a feature needs shared query-key,
hydration, invalidation, or Realtime decisions.

## Campaign rules

Each major contractor-facing feature is an individual campaign with its own roadmap, part packets,
approvals, and completion gates:

1. Clients and Properties
2. Requests and Assessments
3. Sales Pipeline
4. Quotes
5. Jobs
6. Scheduling
7. Invoices and Payments
8. Client Portal
9. Reputation and Magic Review Funnel
10. Automations
11. Dashboard and Reporting
12. Communications
13. Contractor Settings

The numbered lifecycle campaigns express dependency order, not one permanent delivery waterfall.
Communications, Settings, notifications, files, and Platform Owner controls integrate in dependency-ready
slices without taking ownership of another campaign's business rules.

## Jobber research process

Jobber is the default reference for contractor domain models, object relationships, statuses, workflows,
and behavior. A campaign may omit Jobber capabilities or record an approved difference, but it does not
invent a replacement without an explicit product decision. Project wireframes own approved structural
direction; the UpliftContractor design system owns styling and interaction presentation.

Use three evidence passes:

1. Before approving a campaign roadmap, inspect the narrow Jobber skill references and the live product
   for domain vocabulary, relationships, primary journeys, states, permissions, and meaningful edge cases.
2. Before implementing a part, revisit its exact live list, create, detail, edit, conversion, and recovery
   journeys. Record confirmed behavior, omissions, approved differences, and reusable module opportunities
   in that part packet.
3. At the part completion gate, verify the implemented journey against its approved behavior and the live
   reference on desktop and mobile. Match product behavior, not Jobber's visual styling or proprietary copy.

Cross-domain discovery may inspect future Jobber pages to identify reusable modules such as notes,
attachments, tags, line items, visits, schedules, side panels, list controls, and activity surfaces. This
discovery establishes interfaces only; each owning campaign approves and implements its business rules.

## Dependency order

### 1. Clients and Properties

Establish the relationship and work-location model used by every downstream feature.

**Delivered 2026-08-17:** people and companies, lead/customer state, contacts, emails and phones; properties
with addresses, property contacts and access notes, plus add, edit and remove; ownership, tags, notes, files
and timeline; tenant isolation, permissions, search, and create-time duplicate warnings.

**Deliberately left for later**, each with its own reactivation trigger in `Memory/deferred/INDEX.md`:
property deletion guarded by real work, historical address safety, property transfer between clients, the
billing-address shape, and client merge, archive, restore and audit history. Every one of them blocks on work
objects that do not exist yet, or on invoicing.

This unlocks reliable recipient identity, property-scoped work, Communications ownership, Requests, and
downstream lifecycle records.

### 2. Requests and Assessments

Build staff-created and public intake, lead creation, requested services, photos, questions, assessment
scheduling/completion, and terminal conversion behavior. Use the approved choice between request-only,
customer-booked assessment, and direct booking. Conversion prepares Quotes or Jobs without duplicating work.

### 3. Sales Pipeline

Build open opportunities, configurable stages, stage history and aging, owners, next follow-up, values,
Won/Lost outcomes, and explicit creation of operational work. The pipeline tracks commercial opportunity;
it does not replace Requests, Quotes, or Jobs.

### 4. Quotes

Build pricing, packages and add-ons, deposits, secure customer view, versioning, approval/signature,
change requests, follow-ups, and terminal Quote-to-Job conversion. Customer-facing quote access ships with
Quotes rather than waiting for a later generic portal phase.

### 5. Jobs

Build the agreed scope of work, one-off and recurring job forms, assignments, line items, instructions,
job history, costing inputs, and creation from approved/won work. Jobs own the agreement; Visits own each
calendar occurrence.

### 6. Scheduling

Build the unified schedule stream for assessments, visits, events, tasks, quote reminders, and invoice
reminders. Support Scheduled, Anytime, and Unscheduled visits, recurrence edits, assignment, rescheduling,
completion, conflicts, and dispatch foundations.

### 7. Invoices and Payments

Build invoicing from jobs, visits, milestones, batches, or direct customer work; financial history;
partial and manual payments; deposits; reminders; receipts; bad debt; and secure customer payment access.
Online provider processing is an independently gated slice after financial truth is proven.

### 8. Client Portal

Unify secure customer access already introduced by Requests, Quotes, Scheduling, and Invoices. Customers
can request work, view allowed appointments and documents, approve and sign, pay, download receipts, and
see business contact details. Each domain continues to own its business rules.

### 9. Reputation and Magic Review Funnel

Build eligible post-work requests, configurable delays, public-review routing, private service recovery,
reminders, expiry, matching confidence, history, and reporting. Avoid review gating and preserve the
approved boundary between plain operational review requests and promotional marketing.

### 10. Automations

Ship proven one-toggle presets before the custom builder. Then add trigger, conditions, ordered actions,
execution history, delays, retries, stop conditions, and domain-aware safeguards. Automations consume domain
events; they do not become the source of domain truth.

### 11. Dashboard and Reporting

Build summaries and reports only after their source domains have stable meaning. Start with actionable
queues and recent activity, then add lifecycle, financial, operational, and reputation reporting with
permission-aware aggregation.

## Cross-cutting campaign timing

### Communications

Communications owns provider transport, Conversations, messages, participants, attachments, assignment,
delivery history, email/Twilio channel policy, usage, and shared safety controls.

- Operational email and Twilio are separate channel contracts and implementation tracks.
- Package-included email never deducts the phone/SMS Communication Balance.
- Resume the shared Communications foundation after Clients and Properties establishes real contacts,
  contact roles, preferences, ownership, and authorization.
- Integrate request confirmations, quote delivery, visit reminders, invoices, receipts, and review requests
  within the domain campaign that owns each event.
- Add web chat, Messenger, general mailbox ingestion, WhatsApp, and marketing only through separately
  approved tracks.

### Contractor Settings

Build each setting with the feature it controls: Business Profile with shared branding, client roles with
Clients, email identity with Communications, booking with Requests/Scheduling, payments with Invoices, and
automation settings with Automations. Finish the unified Settings navigation and permission model after
these real settings exist.

### Files and attachments

Create one secure file module when the first campaign needs uploads. Its small interface must hide private
storage, tenant authorization, metadata, scanning, variants, retention, and purge behavior. Reuse it from
Clients, Requests, Quotes, Jobs, Invoices, Communications, and Reputation.

### Notifications and activity

Each domain emits its own durable events and actionable notifications. Shared contractor notification
surfaces are built when the first contractor domain needs them. Routine history remains separate from
interruptive notifications.

### Worker infrastructure

Introduce durable worker capability when the first approved asynchronous slice requires it, most likely
Communications. Do not build an empty generic worker platform. The requiring campaign owns the first queue,
retry, idempotency, recovery, and monitoring proof; later workloads reuse that foundation.

### Platform Owner `/jafar`

Parts 0 through 9 are complete. Do not build disconnected provider-control screens ahead of contractor
subsystems. Add dependency-linked Part 10 slices after the controlled resource exists:

- Brevo domains and usage unlock email controls;
- Twilio subaccounts, registrations, numbers, and usage unlock phone/SMS controls;
- payment readiness unlocks processor controls;
- reputation and publishing resources unlock their recovery controls.

Part 11 performs the final Platform Owner A-to-Z audit after the required Part 10 slices close.

## Immediate next action

Open Sales Pipeline Part 1 from `Memory/campaigns/sales-pipeline/NOW.md`. The campaign, fixed seven-stage first
release, and Part 1 schema/permissions/RLS scope were approved on 2026-08-18. Reinspect current implementation
truth, present the exact Part 1 implementation plan named by the packet, and wait for approval before editing
code or migrations.

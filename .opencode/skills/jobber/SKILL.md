---
name: jobber
description: >
  Jobber competitor reference for building the Contractor CRM. Use this skill whenever you are
  implementing or reviewing any part of the Lead → Request → Quote → Job → Invoice → Payment
  lifecycle — including clients, properties, quotes, scheduling, invoices, payments, automations,
  or the client-facing portal. Always consult this skill before making product behavior assumptions,
  designing a status machine, writing business rules for contractor workflows, or deciding how a
  domain object should relate to others. If a task touches contractor CRM product behavior at all,
  read this skill first.
metadata:
  purpose: Jobber competitor reference for AI-assisted Contractor CRM development
  workflow: Lead → Request → Quote → Job → Invoice → Payment
  sources:
    schema: Jobber GraphQL schema — authoritative for object types, field names, enums, mutations
    behavior: Jobber Help Center — UX rules and business logic, cited inline per file
  no_guessing_rule: >
    Field and enum names are taken verbatim from the schema. Behavior is taken from the help center
    with a citation. Anything not confirmed by either source is marked (unverified).
---

# Jobber Reference — Agent Instructions

A precise competitor reference built from two authoritative sources:

1. **Jobber's GraphQL schema** — object types, field names, enums, and mutations. All names are taken verbatim; never invent field names.
2. **Jobber Help Center** — UX behavior and business rules, cited inline with `[[article-slug]]` links. Full URLs at the bottom of each file.

This is a build reference for AI-assisted development, not marketing copy.

---

## Before Reading Any Reference File

Read `jobber-00-overview-lifecycle.md` first whenever:

- The business rule, lifecycle flow, or object relationship is unclear
- You are designing across more than one domain
- You need the master status tables or vocabulary

Then read the narrowest domain file that covers the specific feature. Do not load the full set by default.

Each domain file has three layers:

- **Schema section** — exact field/type/enum names from Jobber's GraphQL schema
- **Help center section** — what Jobber's product does and why
- **§ "How WE compare" section** — the most important part; maps Jobber's model to our own architecture and what to match, adapt, or beat

---

## Module Index

| File                                  | Covers                                                                                                                                                    | Read when working on...                                                                             |
| ------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| `jobber-00-overview-lifecycle.md`     | Vocabulary, full lead→cash lifecycle diagram, object relationship map, master status tables (quote/job/visit/request/invoice/payment), API model basics   | Lifecycle rules, cross-domain design, status machines, object hierarchy, starting a new domain      |
| `jobber-01-clients-properties.md`     | Client object, `isLead` flag, contacts/phones/emails, tags, custom fields, Property model, address geo-coding, billing address, client hub basics         | Contacts, clients, leads, properties, addresses, custom fields, tags, client detail page            |
| `jobber-02-requests-leads.md`         | Request object, Assessment (on-site estimate visit), lead intake flow, `OnlineBookingConfiguration`, `RequestSettings`, self-serve booking types          | Request intake, assessments, lead-to-client conversion, online booking forms, self-serve scheduling |
| `jobber-03-quotes.md`                 | Quote object, line items, good-better-best packages, optional add-ons, deposits, client approval flow, e-signature, Client Hub quote view                 | Quotes, pricing packages, tiered options, deposit collection, approval, digital signature           |
| `jobber-04-jobs-visits-scheduling.md` | Job object (one-off vs recurring), recurrence engine, Visit types (scheduled / anytime / unscheduled), `scheduledItems` unified calendar, team assignment | Jobs, visits, scheduling, recurring work, calendar feed, dispatch, route order                      |
| `jobber-05-invoices-payments.md`      | Invoice object, line items, billing schedule, `PaymentRecord`, Jobber Payments (card/ACH), deposits, dunning, bad debt write-off                          | Invoices, payments, billing, auto-charge, deposits, overdue flow, write-offs                        |
| `jobber-06-automations-clienthub.md`  | Built-in automations (toggle presets), Custom Automation Builder (trigger → condition → action), Client Hub self-serve portal                             | Automations, follow-ups, visit reminders, dunning rules, client portal, online approval/payment     |
| `jobber-07-api-mutations.md`          | Full GraphQL mutation catalog, pagination (Relay cursor), webhooks, rate limits, `userErrors` pattern                                                     | API design, mutation naming conventions, error handling, webhook event catalog, pagination          |

---

## Locked Architecture Decisions

These are confirmed decisions from the **"How WE compare"** sections across all files. Treat as locked unless explicitly revisited.

**Data model**

- **Lead model:** Jobber uses one `Client` row with `isLead: true`. A request from a new person auto-creates the client as a lead. Our `contacts` table with lead/customer status is equivalent — match the "request auto-creates a lead" behavior.
- **Property is the work anchor:** Tax rate, pricing memory, and geo/routing live on the `Property`, not the `Client`. Correct tax calculation and route optimization require property-scoped work objects.
- **Converted status is terminal:** Once a Quote or Request is converted, it never reverts — even if the downstream job is deleted. This prevents double-conversion. Copy this constraint.

**Scheduling**

- **Unified calendar stream:** Jobber's calendar is one polymorphic `scheduledItems` feed (visits + assessments + tasks + events + reminders). Our schedule hub targets the same model.
- **Three visit kinds:** Scheduled (date + time), Anytime (date only, route-ordered), Unscheduled (backlog placeholder with neither). Support all three, don't collapse them.

**Automations**

- **Two-layer model:** Ship both (1) built-in one-toggle presets for the 90% cases and (2) a custom trigger → condition → action builder. Contractors expect presets on by default.
- **Guardrails to copy verbatim:** Day-offset triggers capped at 90 days. Max 6 conditions per automation. Morning = 8 AM local, evening = 7 PM local. Not retroactive. Notify fires on the same channel as the original document.
- **"Update status" action is quote-only** in the custom builder — scope status-changing actions carefully; do not allow arbitrary status writes on every entity.
- **Auto-pay suppresses dunning:** The automation engine must check billing state before chasing an invoice that will auto-charge.

**Client portal**

- **Client Hub is the conversion surface.** Priority parity items: approve + sign + pay deposit on quotes; pay + tip on invoices; request more work (self-serve upsell); view upcoming/past appointments.
- **Branding once, applied everywhere:** Logo and colors set in Business Profile flow into the client portal and booking forms. Single source of truth.
- **Self-serve booking creates a job OR an assessment** — not hardcoded. Match Jobber's `WORK_ORDER` vs `WORK_REQUEST` config choice; some trades want instant booking, others want an estimate visit first.

**API / error handling**

- **`userErrors` pattern:** Mutations can succeed at the HTTP level but return field-level validation errors. Our fixed API error shape (`{ error, field_errors }`) is the equivalent — keep field-level errors first-class.

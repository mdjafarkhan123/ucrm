# Part 6A: Automation Architecture and Desktop UI Blueprint

## Outcome

Approve the smallest secure Automation architecture and every desktop surface before implementation. Product direction is binding in docs/contractor-settings-blueprint.md Part 6.

## Approved behavior

- Presets and build-from-scratch create one immutable-version recipe: When → optional If → ordered Then/Wait → Stop when.
- Platform defaults and organization exceptions govern flexibility; legal, consent, provider, and idempotency protections remain non-overridable.
- Quote follow-up starts after successful delivery, not publication.
- Desktop web only for Part 6.

## Work

- Define the Automation vocabulary and deep module interfaces in permanent documentation.
- Define durable events, transaction ownership, enrollment/claim idempotency, retries, recovery, immutable versions, and safety rechecks.
- Define v1 Quote catalogs and extension seams for later domain packs.
- Design shared entitlement limits, permissions, package overrides, and direct-route denial.
- Decide query/index pairs, cursor pagination, due-work claims, maintained counts, retention, and worker deployment; performance-review the design for 20,000 users.
- Blueprint Settings entry, Automation home, creation/builder/review/detail/history, record controls, Jafar entitlement controls, and retention controls across every desktop state.
- Produce the smallest 6B vertical-slice plan.

## Essential constraints

Reuse existing package/override, Communications, Conversations, audit, cron, and cleanup seams. Customer delivery stays fail-closed until Communications activates it. Routine retention must remain distinct from organization destruction.

## Completion gate

The permanent behavior contract, architecture, performance/security decisions, complete desktop UI blueprint, and 6B plan are explicit and Jafar-approved. No production behavior changes.

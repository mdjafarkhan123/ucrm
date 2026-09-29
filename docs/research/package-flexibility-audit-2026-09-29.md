# Package flexibility audit

Date: 2026-09-29. Scope: Jafar package editor, package APIs, validation, version management SQL,
organization assignment/access resolution, approved contracts, and focused tests. This is a review,
not an approved redesign or a change to customer terms. No live database or browser verification was
performed. Database findings refer to checked-in migrations, including subsequent changes searched
for overrides. Current remote package contents were not independently verified.

## Verdict

The application has a useful versioned entitlement foundation, but does not deliver the requested
freedom to create arbitrary packages. Its approved implementation contract explicitly called for
removing fixed Starter/Growth/Elite assumptions; those assumptions remain in the database, request
validation, UI types, and runtime access resolver. Adding only a Create button would not solve this.

## How it works now

1. A package identity owns draft, published, and retired versions.
2. The Jafar editor changes an existing package's draft: name, description, monthly USD price,
   feature keys, employee seats, email allowances, website chat limits, and automation limits.
3. Publishing freezes that version and retires the previously published version for new selection.
4. An organization is assigned a particular version. Publishing another version does not move it.
5. Effective access combines the assigned version and active organization exceptions; staff
   permissions are also checked. Exceptions can have reasons and effective/expiry dates.
6. Changing an organization's package is an immediate, separately recorded command. Payment and
   paid-through administration are separate; this is not an automatic subscription collection engine.

Useful protections include immutable published features/limits, assignment history, owner-only API
checks, Zod validation, and idempotent organization package-change commands. A later migration allows
members to continue reading their assigned retired versions. Legacy unversioned access remains as
a fallback, so migration away from the old model is incomplete.

## Confirmed gaps and risks

### 1. Only three package identities are permitted

- `src/lib/server/validation/access.schema.ts:3`: fixed three-value enum.
- `src/lib/server/access/effective.ts:5` and `:237`: fixed type and rejecting runtime parser.
- `supabase/migrations/20260101000000_baseline_structure.sql:56099`: database check constraint.
- `src/routes/api/jafar/packages/+server.ts`: listing only; no package creation operation.
- `src/routes/jafar/(protected)/packages/+page.svelte:41`: fixed package-key type; actions create
  versions under existing packages, not new package identities.

This contradicts `docs/jafar-onboarding-implementation-contract.md:79` and the intended owner
flexibility. Display-name changes do not create another independent package.

### 2. Retirement contradicts the screen's promise

The editor says retirement stops new selection while existing organizations keep access
(`+page.svelte:475`). SQL instead raises “Move every organization away from this package before
retiring it” when any current assignment or legacy organization still uses the package
(`baseline_structure.sql:34099`). These behaviors cannot both describe the same action.
There is no restore/reopen operation in the package-management command and retired identities are
excluded from draft creation. No delete-unused-draft action is exposed either.

### 3. One draft save can leave partial changes

`src/routes/api/jafar/packages/versions/+server.ts:32` executes the core package save, then email,
website chat, marketing, and automation writes as separate database calls. An error later returns
409 without undoing earlier calls. The core SQL first deletes **all** draft limits
(`baseline_structure.sql:34186`) and recreates employee seats; subsequent calls restore the others.

Consequences inferred directly from that sequence: a later failure can leave missing limits, a
retry after a failed create can create another draft, and publishing in another tab can freeze a
partially rebuilt configuration. These races were not executed against a database during this review.
Also, marketing/automation inputs are optional with comments promising omission preserves values,
but the preceding unconditional deletion removes those values. That is a contract mismatch even
when every call succeeds.

Recommended correction: one validated transaction for the complete draft, a retry identity for
creation, and publication against a known saved revision.

### 4. Publishing can ignore what is currently displayed in the form

The publish request sends only package key and saved version ID (`+page.svelte:222`). Its button
depends on the confirmation checkbox, not on whether the form differs from the saved draft
(`+page.svelte:775`). Save and publish also use separate pending states.

Example: save $100, edit the field to $150, click Publish without saving. The request publishes
the saved $100 version. Prevent publication while dirty/saving, or provide an atomic Save and
publish action with a review of the exact persisted terms.

### 5. Feature selection is configurable; feature correctness is not proven by a checkbox

The API lists the database feature catalog, excluding only the legacy automation key. Stable
catalog keys are the right model: a new capability still needs implementation and enforcement.
Publication checks require a description, price, and a feature or value explanation, but do not
validate a comprehensive capability-dependency/readiness matrix.

For example, `dispatch.advanced` and `integrations.api` appear in the reference-data catalog, but
the search found no literal runtime references in `src`. That is a readiness question, not proof
of a security bypass or proof that dynamic enforcement is absent. Audit every sellable feature
against its actual screens, API commands, jobs, and limits before presenting it as delivered.

### 6. Package changes lack a consequence preview

`src/lib/components/jafar/organization/AccessWorkspace.svelte:598` offers a target and reason,
then applies the change immediately. `baseline_structure.sql:14603` records the assignment but
does not centrally calculate lost features, excess seats, affected chat widgets, or automations.
It intentionally leaves paid-through dates unchanged. Individual features may enforce their own
limits; this review does not claim those checks are absent.

A move from 20 seats to 5 needs an explicit policy and a preview. Preserve business records;
choose whether cleanup is required first or existing resources remain under restrictions.
Feature-specific behavior must be checked, rather than inferred from a generic package switch.

### 7. Pricing flexibility is deliberately narrow

The version embeds one USD monthly price. Currency and billing period are constrained in SQL.
Annual prices, multiple currencies, add-on billing, and automated collection are not part of this
model. The approved contract explicitly excluded several of these, so absence is a scope choice,
not itself a bug. Separate price records become useful if those choices are now required.

### 8. Documentation and stored allowance terms need reconciliation

`docs/testing/package-permissions.md` still says production package/team screens do not exist.
The reference-data migration header says packages can be added in the console, which the API and
constraints do not support. The deferred note
`Memory/deferred/package-versions-can-have-no-email-limits-configured.md` records mismatches between
some sold versions and approved email allowances. That note is historical evidence; its stated
remote values were not re-queried. Any correction requires new versions and explicit customer moves.

## Primary-source industry comparison

- [Stripe products and prices](https://docs.stripe.com/products-prices/manage-prices): products
  and prices are separate; changed amounts use new prices; archived products preserve existing
  subscriptions. This supports flexible creation and safe withdrawal from sale.
- [Stripe entitlements](https://docs.stripe.com/billing/entitlements?dashboard-or-api=api): stable
  feature keys map products to application capabilities. The app must implement provision/revoke
  behavior; naming a feature does not build it.
- [Chargebee feature management](https://www.chargebee.com/docs/billing/2.0/entitlements/feature-management):
  features have stable identities and typed values, with lifecycle and audit controls.
- [Chargebee grandfathering](https://www.chargebee.com/docs/billing/2.0/entitlements/grandfathering-entitlements):
  applying catalog changes only to new customers versus existing customers is explicit policy.
- [Chargebee overrides](https://apidocs.chargebee.com/docs/api/entitlement_overrides): customer-specific,
  effective-dated exceptions sit over inherited plan entitlements.
- [Stripe changes](https://docs.stripe.com/billing/subscriptions/change-price): billing previews,
  change timing, and payment-success behavior are deliberate parts of plan transitions.
- [Notion downgrade effects](https://www.notion.com/help/plan-downgrade): consequences differ by
  feature, including disabling without deleting and restrictions on future usage.

These are established patterns, not a claim that all leading products implement identical rules.

## Recommended target, subject to Jafar's decisions

Keep stable package identities, published versions, assignment history, and dated customer
exceptions. Remove fixed tier assumptions throughout the system. Let Jafar create and duplicate
packages using supported capabilities and typed limits. Validate combinations before publication.
Archive used packages while retaining existing customers and history; delete only genuinely unused
drafts with no dependent records. Treat stopping sales and terminating customer access as separate
actions. Make complete saves atomic and require an exact reviewable version for publishing.

Decide public versus private offers, which core capabilities are mandatory, monthly-only versus
annual pricing, and downgrade policy before building. Scheduled changes, paid add-ons, trials,
coupons, and automatic billing are additional decisions, not prerequisites for flexible packages.
No literal unlimited capacity claim is made; an expanding catalog will need bounded listing and
history reads when implemented. The current list loads all versions/features/limits together.

## Verification

Ran focused Vitest coverage for package list/write/publish/retire APIs, organization package and
legacy-version assignment, and effective access resolution: **7 files, 41 tests passed**.
The package page's Svelte analyzer returned no issues or suggestions. Passing these checks does
not establish transactional failure safety, browser behavior, full feature enforcement, live
database parity, or production capacity. No database tests were run and no customer assignments
were changed.

Before implementation is called complete, verify dynamic package creation across every layer,
archive with assigned customers, retained-version reads, save failure rollback, concurrent
save/publish, dirty-form publication, feature dependencies, downgrade consequences, and enforcement
for every marketed capability.

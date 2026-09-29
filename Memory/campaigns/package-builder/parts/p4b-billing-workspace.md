# P4b — Billing workspace

**Campaign:** package-builder · **Plan:** `docs/package-builder-behavior-contract.md` § Offsite payment and coverage · ADR 0003 decision 6
**Code:** `main`
**Done when:** in the browser, Jafar can run the P4 example ($149 charge; $100 then $200 received; $151 left as credit; confirm dates) end to end on a test organization, and every test login still sees the same screens.

## Steps

- [x] `POST/GET /api/jafar/organizations/[id]/billing` runs each P4a ledger command (Zod schema `organizationBillingCommandSchema` in `owner.schema.ts`; database messages in cents are turned into dollars)
- [x] Billing tab on the organization page (`BillingWorkspace.svelte`, `BillingActionDialog.svelte`, hover prefetch in `organization-billing-queries.ts`)
- [x] Old commercial POST, its schema, and `CommercialActions.svelte` deleted; the commercial GET stays read-only (Overview and Activity use it)
- [x] `npm run check` has 0 errors (needs `NODE_OPTIONS=--max-old-space-size=8192`)
- [ ] Fix two `state_referenced_locally` warnings in `BillingActionDialog.svelte` (lines reading `billing.today` and `billing.paid_through_date` at mount) — wrap in `untrack` or a `$derived`
- [ ] Directory renewal flag: new migration re-creating `owner_organization_directory` (latest copy in `20260929230000_package_editions_and_agreements.sql`) with two attention reasons — `renewal_due` (active, not on free access, paid-through within the next 7 days) and `payment_overdue` (paid-through passed, grace not ended). Add both to `organization-directory.schema.ts` and the directory page's `attentionMeta` and `emptyTotals`; push with `supabase db push --linked --dry-run` first
- [ ] Unit test for the billing route (auth, Zod 422, step-up 403 for refund/void/correct/adjust, 409 mapping), modeled on `communications/sms/credit-topups/[requestId]/credit-topup-decision.spec.ts`
- [ ] Browser check of the done-when example (log in at `/jafar`), plus a quick look at each test login; then close P4b

## Next

Fix the two warnings, then build the directory renewal flag migration.

## Outside actions

- Directory migration — not yet written or pushed.

## Notes

- Decision to tell Jafar (made in session, not yet approved by him): recording a payment, using credit, adding a charge, and confirming covered dates need no password; refunds, cancellations, payment corrections, and paid-through corrections ask for the password each time (same as SMS money controls). List lives in `billingStepUpActions`.
- Recording a payment pre-fills where the money goes: the charge it was opened from, then due charges oldest first; editing any line switches to manual amounts. Leftover shows as credit.

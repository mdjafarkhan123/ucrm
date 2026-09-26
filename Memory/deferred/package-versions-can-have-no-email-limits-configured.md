# Package versions can have no email limits configured at all

Found 2026-09-26 while browser-verifying operational-email-ses Part 7's over-allowance gate on Raad LTD.

Raad's assigned package (`Elite`, version 2, marked "retired") has `platform_package_version_limits` rows for
`operational_email_recipients` and `essential_email_recipients` both set to `limit_state = 'not_included'`
with no numeric fallback. `resolve_communication_email_allowance` then returns `not_included` for that
organization unless a per-org `organization_limit_overrides` row masks it. Two such overrides (unlimited,
dated 2026-09-06, reasons "any reason" / "Test reason") were the only thing keeping Raad's essential
(invoices/quotes/receipts/security notices) and operational email working — not test debris, load-bearing.

`not_included` is not a chargeable state: `claim_communication_outbox_event` treats it as
`email_allowance_unavailable` and retries forever (15 min backoff) rather than sending or charging. If an
override like this is ever cleared for an organization on a package version with no email limit configured,
that organization's email silently stops sending with no user-facing error — it just retries forever.

**Reactivation trigger:** before the production cutover, or before touching any organization's
`organization_limit_overrides` rows for `operational_email_recipients`/`essential_email_recipients` — check
whether every package version currently assigned to a live organization has real `numeric`/`unlimited` limits
configured for both keys, not `not_included`. Retired/legacy package versions are the likely culprits.

**Constraint already known:** fixing this is a package-data decision (what should Elite v2's real email limits
be?), not a code bug — needs Jafar's input on the right numbers, not just a migration.

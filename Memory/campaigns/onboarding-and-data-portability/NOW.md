# Onboarding & Data Portability: Current Checkpoint

## Goal

Safe assisted import of a new contractor's core records (no duplicates) and full export out — launch-roadmap
Step 2, the second unstarted gate before the first paying customer.

## Where things stand

**Parts 1–3 and 5 are all DONE, COMMITTED-PENDING, and browser-verified.** Only Part 4 (opening balances)
remains, and it is blocked. Campaign is **Paused**. Ownership is now consolidated (2026-09-16): `financial-
reconciliation` Part 6 owns the opening-balance rules, schema, and gate; this campaign's Part 4 owns only the
assisted-import screen that lets an office user enter the two opening facts once that schema exists.

## Next action

None yet. Wait for `financial-reconciliation` Part 6 to land the approved schema and rules, then build the
screen on top of the existing assisted-import pipeline (`import_batches`/`import_rows`, reused with
`entity_type = 'opening_balance'`).

## Blockers

Part 4 blocked on `financial-reconciliation` Part 6 (schema approval + implementation).

Resume command: `continue onboarding and data portability` (will re-check whether `financial-reconciliation`
Part 6 has landed the schema before doing anything).

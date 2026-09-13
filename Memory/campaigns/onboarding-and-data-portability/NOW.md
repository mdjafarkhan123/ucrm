# Onboarding & Data Portability: Current Checkpoint

## Goal

Safe assisted import of a new contractor's core records (no duplicates) and full export out — launch-roadmap
Step 2, the second unstarted gate before the first paying customer.

## Where things stand

**Part 1 (client import) is COMPLETE and COMMITTED.**

**Part 2 (client export) is COMPLETE, BROWSER-VERIFIED, and COMMITTED** (this session). Records-only, instant
download: clients, contacts, contact methods, properties, notes as CSVs + `manifest.json`, zipped with fflate,
streamed straight down. Verified as the Raad LTD owner through the real UI: CSV row counts match the manifest
exactly, no internal-only columns leak, and the 5/min/org rate limit fires correctly under repeated exports.

## Next action

Plan Part 3 (Price Book import/export for `catalog_items`) — reuses the Part 1 import pattern and the Part 2
export pattern. Read `docs/research/onboarding-import-export-research.md` plus the Part 1/2 code
(`src/lib/server/imports/*`, `src/lib/server/exports/*`) before proposing the plan; present it to Jafar for
approval before writing code (Non-Negotiable Rule 3).

## Blockers

None. Part 4 (opening balances) stays blocked on the launch financial-reconciliation audit (Step 3).

Resume command: `continue onboarding and data portability`.

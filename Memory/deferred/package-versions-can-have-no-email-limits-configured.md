# Package versions carry no email allowance

The silent stop is fixed (`20260927160000_email_allowance_never_silently_stops.sql`): a missing or
`not_included` allowance now counts as zero, so essential email sends and optional email is paid from the
Communication Balance. What remains is the package terms themselves.

These versions still say `not_included` for both email keys, against the approved table in
docs/contractor-email-contract.md (Starter 2,500/250, Growth 10,000/1,000, Elite 30,000/3,000):
Starter v3 (published, 1 org: Riverside Legacy Demo), Elite v2 (retired, 2 orgs: Raad LTD, Jaaroweb),
Elite v3 (retired, 0), Growth v3 (draft, 0). Elite v4 (published) is unlimited on purpose.

**Reactivate when:** Jafar plans packages (he parked all package work on 2026-09-27; do not touch packages
before then). Published/retired versions are immutable by trigger, so the correction is new versions through
the Jafar Panel; move organizations only with Jafar's say-so. Open question for then: Elite v4 is unlimited,
the contract says 30,000. Raad's three unlimited overrides are test settings and are no longer load-bearing.

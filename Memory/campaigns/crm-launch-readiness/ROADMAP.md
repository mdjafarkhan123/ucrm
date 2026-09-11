# CRM Launch Readiness Roadmap

This campaign owns the launch promise, gap classification and final sequencing. Feature implementation remains
with its owning domain campaign; infrastructure still requires Jafar's separate topology/migration approval.

| Part | Outcome | State | Dependency | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Establish the contractor-CRM production feature baseline from current primary sources | Complete 2026-09-10 | Existing product definition | Launch, wider-rollout and segment-specific capabilities are separated with sources |
| 2 | Audit current UCRM implementation against that baseline and the approved product promise | Complete 2026-09-10 | Part 1 | Every major product area has evidenced current state, confirmed gap and launch classification |
| 3 | Approve the sell-ready scope and migration/support model | Complete 2026-09-10 | Parts 1–2 | Jafar approved an assisted, opening-state, email/Website Chat, recorded-payment, CSV-accounting, online-only pilot for small established contractors |
| 4 | Publish the final implementation sequence | Complete 2026-09-10 | Part 3 | `docs/crm-launch-implementation-roadmap.md` assigns every promised capability an order, owner, dependency, risk and completion test; exclusions are named |
| 5 | Run the final cross-domain launch audit | Waiting on implementation and production-topology approval | All approved owning campaigns; production topology approval | Security, end-to-end journeys, accessibility, restore/cutover, failure behavior, monitoring and representative load gates pass |

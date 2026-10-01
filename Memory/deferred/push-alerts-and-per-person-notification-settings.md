# Phone and browser push alerts, and per-person notification settings

**Why it waits:** UCRM has an in-app bell and alert emails, but no phone or browser push and no screen where a teammate chooses which alerts reach them and how. Both are CRM-wide, so Jafar decided on 2026-10-01 to keep them out of the Pipeline campaign, which builds only the in-app alert and the email for Task assignments and Note mentions.
**Brings it back:** Plan one CRM-wide notification feature before launch: each teammate's settings per alert type and channel, plus push on phone and browser. Start it as its own campaign.
**Known constraints:** Reuse the existing bell and `team_notifications` alerts. When built, Pipeline Task-assignment and mention alerts must follow these settings and gain push; add that back to `docs/sales-pipeline-behavior-contract.md` § Opportunity Brief actions. Self-assigned Tasks never alert and customers are never notified.

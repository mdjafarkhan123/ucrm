# Quotes Roadmap

Permanent behavior lives in docs/quote-behavior-contract.md.

| Part | Outcome | State | Depends on | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Behavior and architecture approval | Closed | — | Lifecycle, money, version, access, and deposit rules approved |
| 2 | Pricing and Request carry-forward | Closed | 1 | Tenant-safe snapshots and exact calculations |
| 3 | Staff Quote workspace | Closed | 2 | Creation, list, composer, detail, collaboration, and permissions work |
| 4 | Proposals and immutable versions | Closed | 2–3 | Customer-visible versions preserve exact historical truth |
| 5 | Secure access, decisions, signatures, and utilities | Closed | 3–4 | Sharing and customer/staff actions are secure and version-bound |
| 6 | Deposits and payment schedules | Closed | 2, 4–5 | Deposits calculate correctly and gate Job readiness without fake processing |
| 7 | Quote-backed Sales Pipeline | Closed in sales-pipeline | 5–6 | Quote transitions and Pipeline outcome stay atomic |
| 8 | Terminal Job handoff and final audit/manual | Blocked | Jobs foundation | Idempotent conversion preserves Quote history and passes final gates |

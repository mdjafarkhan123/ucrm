# Contractor Settings Roadmap

Permanent behavior lives in docs/contractor-settings-blueprint.md.

| Part | Outcome | State | Depends on | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Settings foundation and Business Profile | Complete except Quotes-owned frozen-branding check | — | Shared identity and responsive permission-aware settings work truthfully |
| 2 | Taxes, Price Book, and Quote Settings | Closed | 1, Quotes | Defaults affect new drafts without rewriting history |
| 3 | Team and access | Partially closed; 3E pending, 3F Scheduling-gated | 1 | Members, roles, permissions, and availability are safely managed |
| 4 | Request and booking forms | Pending | Requests, Scheduling | Public forms and creation outcomes work end to end |
| 5 | Feature-owned settings | Pending by domain | Owning features | Only working features expose settings |
| 6A | Automation architecture and desktop blueprint | Active | Approved product direction | Contract, architecture, full UI blueprint, and 6B plan approved |
| 6B | Entitlements, permissions, limits, and shell | Pending | 6A | Honest allowed, blocked, suspended, and over-limit states |
| 6C | Unified recipe authoring | Pending | 6B | One versioned recipe model supports presets and custom building |
| 6D | Engine and Quote follow-up | Pending | 6C, delivery truth | Idempotent execution, recovery, history, and controls work end to end |
| 6E | Retention and cleanup | Pending | 6D | Safe policy changes and indexed batched cleanup |
| 6F–6H | Dependency-owned integrations and actions | Pending | 6D and owning domains | Each ships only with real triggers/actions and separate approval |
| 6I | Cross-surface completion | Pending | Shipped 6A–6H | Security, performance, accessibility, and desktop journeys pass |

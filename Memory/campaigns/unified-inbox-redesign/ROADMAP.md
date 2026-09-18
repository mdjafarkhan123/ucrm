# Unified inbox redesign roadmap

Source of truth for the visual direction: `docs/research/ghl-unified-inbox-ui-audit-2026-09-18.md`.

| Part | Outcome | State | Dependencies | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Compact workspace shell and real conversation list with honest list controls | Complete 2026-09-18 — desktop light/dark and real-control checks passed | Existing inbox queries and selection behavior | Light/dark desktop comparison and automated checks pass |
| 2 | Compact timeline header, message density, email cards, and jump-to-latest | Complete 2026-09-18 — email/SMS/chat treatment and jump control browser-verified; existing delivery, forwarding, details, review, and identity actions retained | Part 1 | Existing timeline behavior preserved and checks pass |
| 3 | Collapsed/docked composers with real channel safety information | Complete 2026-09-18 — live-verified on Raad LTD: real email send delivered, real website-chat reply sent, SMS composer correctly showed "Not Sent"/Retry (no live Twilio number in this environment — pre-existing, not a redesign defect). Collapse/expand and channel switch (Email/SMS dropdown) all render correctly, zero console errors. The earlier "Conversation history could not be loaded" blocker was a stale test-account password, not a code bug — resolved by Jafar resetting it. Changes not yet committed. | Part 2 | Each available channel sends through the existing flow |
| 4 | Contractor-focused contact/context rail and narrow-screen drawer | Planned | Part 1 | Existing ownership, follower, and related-work behavior preserved |
| 5 | Responsive and accessibility pass across the redesigned workspace | Planned | Parts 1–4 | Keyboard and fixed-width visual checks pass |

# Unified inbox redesign roadmap

Source of truth for the visual direction: `docs/research/ghl-unified-inbox-ui-audit-2026-09-18.md`.

| Part | Outcome | State | Dependencies | Completion gate |
| --- | --- | --- | --- | --- |
| 1 | Compact workspace shell and real conversation list with honest list controls | Complete 2026-09-18 — desktop light/dark and real-control checks passed | Existing inbox queries and selection behavior | Light/dark desktop comparison and automated checks pass |
| 2 | Compact timeline header, message density, email cards, and jump-to-latest | Complete 2026-09-18 — email/SMS/chat treatment and jump control browser-verified; existing delivery, forwarding, details, review, and identity actions retained | Part 1 | Existing timeline behavior preserved and checks pass |
| 3 | Collapsed/docked composers with real channel safety information | Complete and committed 2026-09-18 (`84e865a`). Follow-up polish 2026-09-18: merged `WebsiteChatComposer.svelte` into `ConversationComposer.svelte` (one composer, channel-branched — email/SMS/chat had near-duplicate markup and CSS) and moved the channel picker from the header into the footer toolbar for all three channels. Live-verified on Raad LTD: website chat send, email/SMS channel switch, footer layout all correct, zero console errors. Committed `e5c058f`. | Part 2 | Each available channel sends through the existing flow |
| 4 | Contractor-focused contact/context rail and narrow-screen drawer | Planned | Part 1 | Existing ownership, follower, and related-work behavior preserved |
| 5 | Responsive and accessibility pass across the redesigned workspace | Planned | Parts 1–4 | Keyboard and fixed-width visual checks pass |

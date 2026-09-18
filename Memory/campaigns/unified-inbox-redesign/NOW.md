# Unified inbox redesign — now

- Goal: renew the existing inbox surface in separately verified slices without inventing unsupported behavior.
- Active part: Slice 3 — docked composer. Core behavior complete and committed. Follow-up polish (merge WebsiteChatComposer into ConversationComposer; move channel picker to the footer) is done and browser-verified 2026-09-18, not yet committed.
- Exact next action: commit the composer-merge/footer-polish change (see ROADMAP.md Part 3 note), then ask Jafar if any more Slice 3 polish is wanted or start Slice 4 (contact/context rail + narrow-screen drawer).
- Blockers: none. Slice 4 has no known blocker (depends only on Part 1, already done).
- Pointers: `Memory/campaigns/unified-inbox-redesign/ROADMAP.md`; `src/lib/components/communications/ConversationComposer.svelte` (now handles email/SMS/website_chat); `src/lib/components/communications/ComposerChannelMenu.svelte`.

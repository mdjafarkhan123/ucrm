# Unified inbox redesign — now

- Goal: renew the existing inbox surface in separately verified slices without inventing unsupported behavior.
- Active part: none — Parts 1–6 complete and committed 2026-09-21 (Part 6 keyboard/accessibility also darkened the shared light-theme green token `--color-interactive`). Only remaining item: the deferred stop/undo timeline line (needs a new item type in the merged timeline); build it only if Jafar asks, otherwise the campaign can be completed and removed.
- Jafar decided 2026-09-21: desktop app only — no mobile/narrow-window verification. The ≤1050px drawer opened and switched tabs fine once; nothing more to check. Unlinked-sender panel could not be checked (every Raad LTD conversation is linked); skip unless one appears.
- Part 5 (stop texting a customer) DONE 2026-09-21, industry pattern (Jobber/HighLevel/Twilio): per-number staff stop (any member who can reply), customer STOP locked (only START lifts), staff stop undoable (restores earlier consent exactly), marketing email shown read-only. Migration `20260921140000` applied to the linked project. Research: `docs/research/ghl-inbox-dnd-controls-2026-09-21.md`.
- Jafar must do himself: sign in as the `finance` and `sales` test logins and confirm amounts are hidden without price permission (browser rules forbid me typing passwords). Server side is already proven by tests.
- Decided 2026-09-21: Send Later stays email-only; Website Chat never gets it.
- Blockers: none. Another agent works on a different campaign; unrelated modified files in `git status` are not ours (stage only the files above).
- Pointers: `Memory/campaigns/unified-inbox-redesign/parts/part-4-context-rail.md`; roadmap: `Memory/campaigns/unified-inbox-redesign/ROADMAP.md`. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=6144` on this machine.

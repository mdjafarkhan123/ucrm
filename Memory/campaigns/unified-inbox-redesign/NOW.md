# Unified inbox redesign — now

- Goal: renew the existing inbox surface in separately verified slices without inventing unsupported behavior.
- State 2026-09-21: Parts 1–7 are all built and committed (Part 7 = the commit right after `4764e45`, "Unified inbox Part 7").
- Exact next action: Jafar signs in himself as the `sales` test login in the automation browser (I cannot type passwords, and there is no view-as feature). Then finish the check below and close the campaign: remove its registry row in `Memory/INDEX.md` and delete `Memory/campaigns/unified-inbox-redesign/` (product truth already lives in `docs/research/ghl-inbox-dnd-controls-2026-09-21.md`). If Jafar prefers to skip the browser check, close it now noting the check was skipped.
- The finance/sales check, as originally worded, cannot show hidden amounts: checked 2026-09-21, the `finance`, `sales` and `office` roles all hold `quotes.view_price` and `jobs.view_price` by default, none has personal overrides, and none has `invoices.view` or `conversations.send` (owner/admin only). To see amounts hidden, the price permissions must first be removed from that test member (permissions change — ask Jafar first, restore afterwards). Server side is already proven by `context.spec.ts` (12 tests pass, incl. "withholds money … without the price permission").
- Open, only if wanted later: the customer's own STOP/START as lines in the thread (needs a real customer STOP to verify against); the unlinked-sender panel was never checked because every Raad LTD conversation is linked.
- Decided: desktop app only. Send Later stays email-only; Website Chat never gets it.
- Blockers: none. `npm run check` needs `NODE_OPTIONS=--max-old-space-size=6144` on this machine.

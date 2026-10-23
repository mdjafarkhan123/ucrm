# Part 7 — Reply

**State:** Built and merged to main 2026-10-23 (branch `claude/messenger-part7`). Migration
`20270102090000_messenger_reply.sql` applied and recorded. Left: the live proof.

**What it does:** the reply box sends on Messenger (text only, ≤2,000 characters; snippets shown, no files). The
database refuses with a plain reason when the Page is off/needs reconnect or the 24-hour window is closed, and the
claim re-checks both before every try. Worker `messenger-send-worker.ts` (Send API `RESPONSE`, intent ID as
`metadata`) runs at once from the reply route and from the one-minute Messenger cron (dispatch now also wakes for
waiting replies). Webhook reports: delivered/read watermarks → Sent / Delivered / Seen ticks (Seen = filled circle,
design `inbox.md`); our echo settles an unknown outcome; an echo from another app (Page's Facebook inbox) is added
as "Sent from Facebook". Token/permission refusal sets the Page to `needs_reconnect`. Messenger replies have no
Resend. Not built: Human Agent tag (Part 10), files on Messenger (later, needs Jafar's call).

**Proof so far:** a rolled-back run of the migration on the live database (queue, same-key repeat, different
words refused, 2,001 characters refused, claim/finalize/refinalize, own echo, delivered → read, no step back,
foreign echo once, unknown settled by echo, token refusal → reconnect, closed window refused at queue and
cancelled at claim, stale claim quarantined). Vitest: Messenger + communications suites 252 passed; 1 failure in
`number-readiness.spec.ts` is unrelated (also on main).

**Next:** with Jafar's yes and Chrome connected, send a reply to the test lead "Facebook user" in the live inbox;
Jafar confirms it arrives on his tester account and opens it; check Delivered then Seen in the inbox; screenshot
beside Pencil `np8WS`/`j93I8l`. The window runs 24 h from that customer's last message (2026-10-23 01:59 UTC).

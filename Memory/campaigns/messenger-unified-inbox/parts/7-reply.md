# Part 7 — Reply

**State:** Done 2026-10-23 (branch `claude/messenger-part7`, merged). Migration
`20270102090000_messenger_reply.sql` applied and recorded.

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

**Live proof (2026-10-23):** with Jafar's yes, "Test reply from Uplift CRM" sent from the live inbox; Facebook
accepted it, our echo matched it (one row), Jafar received it on his tester account and opened it; the inbox showed
Seen for it and for a second CRM reply. Seen circle re-centred after Jafar spotted it off-centre. Not yet seen live:
a reply typed in Facebook's own Page inbox ("Sent from Facebook") — Jafar agreed the CRM shows every message.

**Next:** Part 8.

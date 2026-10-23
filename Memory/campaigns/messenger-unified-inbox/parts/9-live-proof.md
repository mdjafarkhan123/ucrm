# Part 9 — Live proof

**State:** In progress 2026-10-23 (branch `claude/messenger-part9`, merged to main as it goes).

**Proven live (Chrome, Raad LTD owner, 1440):**
1. Tester "hi there" → saved once in 0.6 s, shown under Facebook user; CRM reply delivered → Seen.
2. Reply typed in the Page's Facebook inbox → shown in the thread (after fix A, appears without reload).
3. 24-hour window closed (page clock moved +25 h): "Reply window closed" chip, reason, Send disabled, "Reply by text".

**Fixed during Part 9 (Jafar asked for real-world inbox behaviour):**
- A. Foreign echo never refreshed open inboxes: delivery-activity trigger was update-only. Migration
  `20270105090000_inbox_activity_on_new_send.sql` (applied) broadcasts on insert of non-automated sends.
- B. "Needs reply" meant unread. Now `ConversationGroup.awaitingReply` (customer spoke last, Front/Intercom);
  automated sends, forwards, chat system lines and auto-responders ignored. Tests in `inbox.spec.ts`.
- C. Jafar's channel logos: `src/lib/assets/channels/*.png` (imported for hashed URLs); bubbles keep white mark.

**Remaining:** 4 revoke access on Facebook → "reconnect needed" → reconnect (Jafar said yes); 5 Meta dashboard
webhook check + recovery steps; evidence README `docs/evidence/messenger-part9/`; Pencil redraw of logos later.
**Noted, waiting for Jafar:** Settings Pages table squashes the Page name ("U.."); Messenger settings header uses
a phone icon; Text and Website chat logos look alike.

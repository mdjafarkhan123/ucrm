# Messenger in the Unified Inbox — roadmap

**Plan:** `docs/messenger-behavior-contract.md` — scope approved 2026-10-18; build order below is the approved workflow, parts 3 onward still need Jafar's go-ahead after Part 2.

| Part | Plan section | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- | --- |
| 1 Meta app dashboard setup | Assumptions | Test Page, tester roles, Facebook Login for Business ready | — | Jafar's Facebook account has a role and can pick the test Page; webhook URL is added in Part 5, not here | In progress |
| 1b Business portfolio + Business Verification | Assumptions | Portfolio created and linked to the app; verification submitted early because review takes days | — | Submitted and "In review" in Security Center (approval is Part 10's gate); trade license in hand 2026-10-18 | Verified 2026-10-18; app link pending |
| 2 Plan: Messenger research | Still unclear | `docs/research/messenger-transport-webhooks.md`; open questions answered | — | Unverified Meta facts closed; Jafar approved plan and the three open choices | Done 2026-10-23 |
| 3 Database foundation | First version | Channel Connection and Identity tables, encrypted Page token, widened channel checks | 2 | Migration applied with the CLAUDE.md `psql` recipe; existing SMS/email tests still pass | Not started |
| 4 Connect and disconnect a Page | First version: Connect | Settings → Communications → Messenger card; test message; disconnect | 3, Pencil design | Jafar connects the test Page in the live app and disconnects it | Not started |
| 5 Inbound webhook | Rules | Handshake, signed POST, size cap, save-first, dedupe; then add callback URL + verify token in Meta dashboard | 3 | Meta test event and a real message are stored once; repeat delivery makes no duplicate | Not started |
| 6 Inbox shows Messenger | First version: Receive | Messenger in feed, client/lead linking, composer channel | 5, Pencil design | Test message appears under a lead in the live inbox | Not started |
| 7 Reply | First version: Reply | Reply branch, 24-hour window check, worker, delivered/read states | 6 | Reply reaches the test account; window-closed state shows a reason | Not started |
| 8 Hardening and performance | Health | Token expiry, revoked permission, webhook auto-disabled recovery, many Pages, performance verdict | 7 | Each health state shows "reconnect"; `performance-review` verdict recorded | Not started |
| 9 Live proof | Success checks | Full journey on the live app, screenshots next to Pencil | 1–8 | Jafar sees it work; evidence recorded; committed and pushed | Not started |
| 10 Go-live (Jafar-owned) | Not doing | Verification approved (from 1b), privacy and data-deletion URLs, App Review including the Human Agent (7-day reply) feature | 9, 1b approved | Meta grants Advanced Access | Not started |

**Code to reuse:** webhooks `src/routes/api/webhooks/{twilio,stripe,ses-inbound}` (Stripe's per-connection URL is the closest);
Stripe connect `src/lib/server/payments/stripe-connection.ts` and `stripe-credential-crypto.ts`; send path
`src/lib/server/communications/{drain,sms-worker}.ts` and `enqueue_conversation_reply_sms`; inbound RPC
`record_communication_sms_inbound_message`; Zod `src/lib/server/validation/communications.schema.ts`; channel unions in
`src/lib/communications/inbox.ts`. Known gaps: `email|sms` check constraints, `client_contact_method_id NOT NULL`, no
body-size cap on any webhook, no GET handshake route yet.

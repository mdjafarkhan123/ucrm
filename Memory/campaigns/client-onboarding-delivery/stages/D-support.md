# Client onboarding and delivery — stage D: Support chat

Before D1, run the `performance-review` design branch: live updates grow with signed-in users across tenants.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| D1 Chat + inbox | §7 Chat with Uplift button, one thread, `/jafar` Support Inbox, Uplift Support + responder name | — | Contractor sends, Jafar replies, both see it; customer inbox unaffected | Done 2026-10-01 |
| D2 Live + unread | Real-time delivery when open, unread badges | D1 | Reply appears without refresh; badge clears on read | Done 2026-10-01 |
| D3 Who sees what | Owners/admins see all org threads; others see own and added ones | D1 | Field member cannot see the owner's thread | Done 2026-10-01 |
| D4a Chats + topics | A new chat per question (Intercom model, Jafar 2026-10-02), past chats listed, topic per chat (optional, starts Other; starter/admin/Uplift change it with a grey line), topic filter in `/jafar` | D1 | A member starts two chats with different topics; `/jafar` filter shows only the matching one | Done 2026-10-02 |
| D4b Attachments | Photos and documents, up to 5 files / 20 MB per message, both sides; photos show in the chat, other files download; program files blocked | D4a | A photo attaches and opens; a PDF downloads | In progress — `parts/D4b-attachments.md` |
| D5 Follow-up | Email after a delayed unread reply, resolve/reopen, Jafar starts a thread, visible on suspended screens | D2 | Unread reply emails once; reopened thread keeps history | Not started |
| D6 Ask Uplift | Ask Uplift from a wizard section with that section attached | D1, B1 | Jafar sees which section the question came from | Not started |

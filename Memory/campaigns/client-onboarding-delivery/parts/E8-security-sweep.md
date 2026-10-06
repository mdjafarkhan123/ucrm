# E8 — Security sweep

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §9
**Code:** `main`
**Done when:** The sweep finds no password or secret in answers, logs, chat, emails or owner screens, and access checks hold.

## Steps

- [x] Database (dev, 2026-10-06): every setup/support table has row security; nobody signed out can read any; signed-in people cannot write directly; every callable setup/support function checks the person's business and role; `private` schema unreachable from the browser
- [x] Live refusal test in a rolled-back transaction: another business's owner, Raad's field member and sales member can neither read Raad's setup nor change it; the field member sees only his own chats
- [x] Every `/api/setup`, `/api/support`, `/api/jafar/setup`, `/api/jafar/support` and Jafar's organization setup route checks the login; writes are validated
- [x] No question (published or draft) asks for a password, PIN or card; live chat pings carry ids only; Jafar's live channel is a 64-hex secret tied to his session; protected documents open for owner and Jafar only
- [ ] Jafar's decision on the two gaps below, then build it

## Next

Waiting on Jafar. Question, word for word: "Nothing asks for a password, but nothing stops one being typed. If a client pastes a password or card number into a setup answer or a chat, it is saved, and a chat message is copied into the 'you have a reply' email. Should the app warn them before sending when text looks like a card number or a password/key (like Zendesk and GitHub do), or leave it?"

## Notes

- Small second gap: error logs print the database error, which for a refused row can include the typed values. Fix with the warning work if Jafar wants it.
- Supabase's advisor lists the setup/support functions as "callable by signed-in users"; that is the project's normal pattern and each checks permission inside.

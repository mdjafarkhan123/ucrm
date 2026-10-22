# Batch 66 · Website chat widget

**Board:** `concept.pen` → "Concept · Batch 66 · Website chat widget · Options A and B · 2026-10-22" (`yyWfm`),
right of Batch 65. **Waiting for Jafar's choice.** Piece: `src/widget/website-chat.ts` (list-3, outside the
coverage command). Built into `static/widget/website-chat.js` by `vite.config.widget.ts`; Shadow DOM, own `--wc-*`
tokens, light colours on every site, colour from Branding.

## Research

Settled evidence reused: `Design/Website Chat/evidence-notes.md` (HighLevel form, Intercom thread) and
`docs/research/website-chat-channel-review.md`. Checked 2026-10-22: Intercom Messenger home (logo, reply
expectations), Podium Webchat (text-back for home services), Zendesk persistent messaging.

## Live behaviour kept

Launcher (bottom left or right) and teaser with dismiss; header with business name and close; greeting; Name,
phone with searchable country, email, message; "Text me about my request" agreement shown once a phone is typed;
privacy link; Send; inline field errors and form banner; loading skeleton; chat with earlier messages, sending,
"Not sent — tap to retry", composer; ended + Start a new conversation; not set up / not available; Powered by
the business.

## Options (sample business Raad LTD Builders, brand `#0F766E`, on a 1440 sample website)

- **A · Chat thread** (open `q5TQJp`, closed corner `sMtW5`, chat `A6Ebuq`, ended `sdpYM`, unavailable `RneiJ`):
  improved live look. Brand top with the logo on white, greeting as the first message, the details form as a
  white card inside the chat, round launcher.
- **B · Welcome card** (open `rt68g`, closed corner `R8Hcc`, chat `G99We`, ended `VNvic`, unavailable `h0r6K`):
  new concept. Tall brand top with a big question, one white card: message first, then name/phone/email in one
  joined box, agreement in a grey box, big Send. Chat gets a slim white top, grey reply bubbles, pill message box.
  "Message us" pill launcher; speech-bubble teaser with a round × above.

## New behaviour to approve with the option

Logo from Branding in the widget (today initials; initials stay when no logo); copy "Email (optional)", "We'll
reply right here", "Not sent · Tap to retry"; B only: message-first order and the "Message us" label.

## After approval

Draw form mistakes, the country search list, loading and sending for the chosen option; delete the other; record
the yes here and in list-3; look rules into the design skill (new § Website chat widget). Then Jafar's Ctrl+S and
commit `concept.pen` from main.

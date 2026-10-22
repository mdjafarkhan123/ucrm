# Batch 66 · Website chat widget

**Board:** `concept.pen` → "Concept · Batch 66 · Website chat widget · Options A and B · 2026-10-22" (`yyWfm`),
right of Batch 65. **Approved B (Welcome card) by Jafar 2026-10-22**; Option A removed from the board. Piece: `src/widget/website-chat.ts` (list-3, outside the
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

## Approved B (sample business Raad LTD Builders, brand `#0F766E`, on a 1440 sample website)

Open `rt68g`, closed corner `R8Hcc`, chat `G99We`, ended `VNvic`, unavailable `h0r6K`. Tall brand top with a big
question, one white card: message first, then name/phone/email in one joined box, agreement in a grey box, big
Send. Chat: slim white top, grey reply bubbles, pill message box. "Message us" pill launcher; speech-bubble teaser.
Form states drawn after approval (`iVS2R`): just opened, mistakes, country list, loading, sending, couldn't send.
Look rules: design `layout.md` § Website chat widget.

## New behaviour (approved with B)

Logo from Branding in the widget (today initials; initials stay when no logo; needs the logo in the widget's
public config); copy "Email (optional)", "We'll reply right here", "Not sent · Tap to retry", friendlier field
errors ("Enter your full name.", "Enter the whole phone number…") instead of "Invalid value"; message-first
order; "Message us" pill label.

## Build (2026-10-22)

Built on `claude/build-batch66-website-chat`: `src/widget/website-chat.ts` restyled to every drawn state, logo from
Branding through `logoPath` in the public config and `src/routes/api/webchat/logo/+server.ts`, friendlier mistakes.
Evidence: `docs/evidence/2026-10-22-batch66/README.md`.

## Done (2026-10-22, Jafar: "please fix all")

- Chat-message trigger bug fixed (`supabase/migrations/20261022120000_customer_reply_trigger_chat_messages.sql`,
  applied live); a real widget send and follow-up landed linked to the client (shot 11).
- Settings preview `WebsiteChatPreview.svelte` restyled to the widget (shots 12–14, light and dark).
- Pencil `yyWfm` tidied (decision note removed, intro says built). Needs Jafar's Ctrl+S, then a `concept.pen` commit.

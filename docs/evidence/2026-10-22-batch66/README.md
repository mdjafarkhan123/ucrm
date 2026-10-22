# Batch 66 · Website chat widget built (approved B, Welcome card)

Pencil: `concept.pen` → `yyWfm` (`rt68g` open, `G99We` chat, `iVS2R` form states; exports here beside the live shots).
Look rules: design `layout.md` § Website chat widget.

Checked 2026-10-22 at 1440 on a sample contractor page (`127.0.0.1:5174`, an allowed origin of the Raad LTD widget)
loading the widget from this branch's dev server:

| Shot | State |
| --- | --- |
| 01 | Closed: "Message us" pill |
| 02 | Just opened: welcome top with the Branding logo, message-first card, Send greyed out, open launcher is a chevron |
| 03 | Mistakes: red contact box, alert marks, plain-words fixes under the box, agreement shown once a phone is typed |
| 04 | Country list: search, chosen row with check, brand edge on the country button |
| 05 | Sending: spinner and "Sending…", cannot be pressed twice |
| 06–07 | Conversation: slim white top, grouped business bubbles with the logo on the last, brand visitor bubbles, "Not sent · Tap to retry" |
| 08 | Ended: card with "Start a new conversation" |
| 09 | Not available: welcome top, card with the icon tile, no footer |
| 10 | Teaser speech bubble with its own round × (dismiss checked: teaser gone) |

Real server answers: config now returns `logoPath`; `GET /api/webchat/logo` returns the 77 kB PNG (200). Shots 05–08
use sample server answers because a live first message currently fails in the database: the shared trigger
`private.opportunity_record_customer_reply` reads `new.in_reply_to_intent_id`, which `website_chat_messages` does not
have (error 42703). Reported to Jafar; fix waits for his yes, then the live send needs one proof.

## Fixes (same day, Jafar: "please fix all")

- **Trigger bug fixed** by `supabase/migrations/20261022120000_customer_reply_trigger_chat_messages.sql` (applied with
  psql and recorded). Shot 11: a real send through the live app (`localhost:5173`) — first message and follow-up
  both saved in `website_chat_messages`, linked to the client; the greeting opens the thread.
- **Settings preview** (`Settings › Website chat › Edit`) redrawn as the new widget. Shots 12–14: open, closed with
  teaser, and Mobile size, in light and dark; it keeps light colours in dark mode like the live widget.

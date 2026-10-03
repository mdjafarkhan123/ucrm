# D5b — Reply emails

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 7 Follow-up
**Code:** `main`
**Done when:** Unseen reply emails once; an opened one sends none

## Steps

- [x] Performance design: a due-reminder table (Intercom's unread-conversation email); the email worker's
  once-a-minute wake sends what is due. Work grows with unseen replies only
- [x] Database change written: `supabase/migrations/20261006180000_support_unseen_reply_emails.sql`
- [x] Apply it; database checks (reply → reminder; read clears; due list; removed teammate dropped)
- [x] Email sender in `src/lib/server/support/`, called from the email-worker wake (like owner alerts);
  Jafar's copy goes to the owner alert recipients
- [x] Messenger opens the chat from the email link (`?support_chat=<id>`); Jafar's link is `/jafar/support?thread=<id>`
- [x] Unit tests (`unseen-reply-emails.spec.ts`)
- [ ] Real run: a reply left unseen emails once; opening stops it; Open chat link opens the chat; performance verification

## Next

Real run: reply from `/jafar/support` to the field tester's chat, wait 4 minutes, check the outbox row
(`platform_outbox_deliveries`, key `support-unseen:%`) and that no second one appears; then open the link.

## Outside actions

- Apply migration `20261006180000_support_unseen_reply_emails` — check: `list_migrations` shows it and
  table `support_unseen_reply_reminders` exists — done

## Notes

Signing in does not return to the page you came from, so an email link opened while signed out lands on the
dashboard without opening the chat. Defer, don't fix here.

# D4b — Attachments

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 7
**Code:** `main`
**Done when:** A photo attaches and opens; a PDF downloads.

## Steps

- [x] Database change applied (`20261006150000_support_attachments`) and types regenerated
- [x] Server: upload-link, send, and view/download routes on both sides (`src/lib/server/support/attachments.ts`)
- [x] Screens: paperclip, photo thumbnails opening `ui/Lightbox`, download rows, paste-to-attach
      (`SupportConversation.svelte`; `ConversationAttachments.svelte` extended with `presign`, `maxFiles`,
      `triggerFirst`, `onReadyChange`, `add()`)
- [x] `npm run check` 0 errors; chat tests pass, including new `attachments.spec.ts` on both sides
- [ ] Database refusals checked by hand: wrong prefix, renamed program file, 6 files, over 20 MB
- [ ] `svelte-autofixer` on `SupportConversation.svelte` and `ConversationAttachments.svelte`
- [ ] Browser run, member side and `/jafar` Support Inbox: send a photo and a PDF each way; photo opens big
      and steps with arrows; PDF downloads; files-only message shows "Sent a file" in the chat lists

## Next

Run the remaining database refusal checks with `execute_sql` against
`private.check_support_attachments` (the "ok", "no extension" and "empty" cases already passed), then the
autofixer, then the browser run. In the browser, watch two things: the big photo view must sit above the
messenger panel, and pressing Escape in it must close only the photo, not the messenger too.

## Outside actions

- Apply migration `20261006150000_support_attachments` — check: listed by `npx supabase migration list` —
  done 2026-10-02

## Notes

Follows the customer inbox's paperclip (upload on pick, then send) and Intercom's messenger: a message may be
files with no words. Photos stream through our own route, as the design rule asks; other files download
through a short-lived link. Uplift's files are stored under the contractor's organization.

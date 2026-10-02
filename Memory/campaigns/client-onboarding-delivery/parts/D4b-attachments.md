# D4b — Attachments

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 7
**Code:** `main`
**Done when:** A photo attaches and opens; a PDF downloads.

## Steps

- [x] Database change written: `supabase/migrations/20261006150000_support_attachments.sql`
- [ ] Database change applied (`npx supabase db push --linked`, dry-run first) and types regenerated (`npm run db:types`)
- [ ] Server: upload-link routes, send routes accept files, view/download routes — both sides
- [ ] Screens: paperclip in the chat box, photos as thumbnails that open big, other files as download rows
- [ ] Tests, checks, and a browser run with a photo and a PDF from both sides

## Next

Apply the database change, then build the server routes.

## Outside actions

- Apply migration `20261006150000_support_attachments` — check: it appears in `npx supabase migration list`
  (remote column) and `public.support_message_attachments` exists — pending

## Notes

Follows the customer inbox's paperclip (upload on pick, then send) and Intercom's messenger: a message may be
files with no words. Photos stream through our own route, as the design rule asks; other files download
through a short-lived link.

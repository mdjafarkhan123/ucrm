# Uplift's emails ignore the saved sender name and reply-to

**Why it waits:** `/jafar/settings/email-sender` saves a sender name and reply-to address, but platform
emails (`src/lib/server/email/brevo.ts`) send from `SYSTEM_FROM_EMAIL` with no name and no reply-to.
Using them changes what every prospect and client sees, so Jafar decides first.
**Brings it back:** Jafar says to wire them, or Uplift mailboxes (next release) replace the sending route.
**Known constraints:** the Settings page tells Jafar the values are not used yet; update that copy and
the card description in `src/lib/jafar/owner-settings.ts` when this is done.

# Batch 45 — Notification bell pop-up, built 2026-10-21

Checked live at 1440-class desktop width on the contractor owner login (Raad LTD), signed in on a local dev server.

- Light mode, loaded: `bell-light-needs-you-and-latest.png`. The two orange "Needs you" cards are **simulated** (the
  browser's `/api/notifications` answer was extended in the page, nothing was written to the database); the timeline
  below them is the account's real alerts.
- Dark mode, loaded: seen on the same screen (Needs you cards, timeline, unread dot, Mark all read, close ×).
- Empty ("No notifications yet", "All caught up") and couldn't load ("Try again") were forced the same way and
  looked as drawn.
- Not shown live: the loading bones, the Mark-all-read failure strip, and Jafar's panel foot ("View all
  notifications"); the last is the same shared panel with a full-width secondary button.

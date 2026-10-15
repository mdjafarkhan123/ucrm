# Unified inbox — new Classic concept

**Stage:** Design, waiting for Jafar's yes. Pulled forward from stage W at Jafar's request on 2026-10-15.
**Claim:** `36d90015fdd6` (`classic-pen-inbox`), branch `claude/inbox-design`, folder `.worktrees/inbox-design`.

**Pencil:** `Communications · Inbox · 1440` in `classic.pen` (x 3080, y 5790), light theme; dark checked by
switching the frame's theme. Not committed yet: Jafar presses Ctrl+S, then commit `classic.pen` from main.

**Concept:** three separate cards on the grey page (list 320 · conversation · customer 344), slim sidebar as on
Schedule, no page title (Jafar's 2026-08-25 choice). Jafar asked if it was new; answer given: an improvement of
the live three-column layout. He chose to keep it and asked for a chat-like timeline and coloured channel icons.
Live behaviour came from `src/routes/(app)/communications/+page.svelte` and `src/lib/components/communications/*`.

**Jafar's permission (2026-10-15):** for this screen he said "you can add remove button, introduce new
element". Each addition still needs his yes before it joins the plan's § Approved additions:

1. Filter button beside the list search (HighLevel filters; inbox contract § Inbox handling).
2. Assignee picker and Follow moved from the Contact tab into the conversation header.
3. Header Mark as unread, Archive and More (…). Opening already marks read, so the button is "unread" (Jobber).
4. "New" divider above messages that arrived since the last visit (HighLevel).
5. Internal notes with @mentions, and a Reply / Internal note switch in the composer (inbox contract).
6. Dark "Open job" featured card in the customer panel: next visit, crew, approved quote, Open job.
7. Address row; Call / Text / Email quick buttons under the customer's name.
8. Chat timeline: every message is a bubble (customer left, team right), time and delivery ticks under the
   bubble, email replies show a quoted original, Details / Forward / More appear on hover.
9. List: short chat times (10:11 AM, Yesterday, Oct 13) and "You:" / "Auto:" before outbound previews.

**Colour meaning:** channels — Email blue, Text green, Website chat teal (list avatar badges, bubble meta,
composer, contact tiles). Unread and the New divider in Communications blue; needs review amber; internal
notes violet (Team); customer-panel tabs in record-type colours; sent bubbles use `classic2-selected`.

**Drawn state:** text-reply composer (no subject, segment estimate, single Send). The email composer (subject,
templates, Send later) still needs drawing in a states frame before build.

**Next:** record Jafar's yes or changes here; then add the agreed additions to the plan, commit `classic.pen`
from main, and draw the remaining states (email composer, empty, loading, needs-review, chat ended).

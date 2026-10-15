# Unified inbox — new Classic concept

**Stage:** Design, waiting for Jafar's yes. Pulled forward from stage W at Jafar's request on 2026-10-15.
**Claim:** `36d90015fdd6` (`classic-pen-inbox`), branch `claude/inbox-design`, folder `.worktrees/inbox-design`.

**Pencil:** `Communications · Inbox · 1440` in `classic.pen` (x 3080, y 5790), light theme; dark checked by
switching the frame's theme. Not committed yet: Jafar presses Ctrl+S, then commit `classic.pen` from main.

**Concept:** three separate cards on the grey page (list 320 · conversation · customer 344), slim sidebar as on
Schedule, no page title (Jafar's 2026-08-25 choice). Live behaviour came from
`src/routes/(app)/communications/+page.svelte` and `src/lib/components/communications/*`.

**Jafar's permission (2026-10-15):** for this screen he said "you can add remove button, introduce new
element". Each addition below still needs his yes before it joins the plan's § Approved additions:

1. Filter button beside the list search (HighLevel filters; inbox contract § Inbox handling).
2. Assignee picker and Follow moved from the Contact tab into the conversation header.
3. Header Mark as unread, Archive and More (…) buttons. Opening already marks read in the live app, so the
   button is "unread", as Jobber offers.
4. "New" divider above messages that arrived since the last visit (HighLevel).
5. Internal notes with @mentions in the timeline, and a Reply / Internal note switch in the composer
   (inbox contract § Team collaboration; not built yet).
6. Dark "Open job" featured card at the top of the customer panel: next visit, crew, approved quote, Open job.
7. Address row in Contact. Channel badge on list avatars, labelled Send button, Ctrl + Enter hint.

**Colour meaning used:** unread counts and the New divider in Communications blue; needs review amber;
internal notes violet (Team); customer-panel tab icons in record-type colours; sent texts use
`classic2-selected` (near-black in light, brand green in dark).

**Next:** show Jafar, record his yes or changes here. After approval: add the agreed additions to the plan,
commit `classic.pen` from main, then plan the build with the inbox contract owner rules.

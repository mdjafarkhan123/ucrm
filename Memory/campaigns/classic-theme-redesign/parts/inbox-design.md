# Unified inbox — new Classic concept

**Stage:** Design approved — Jafar said "approved." on 2026-10-15 for `Communications · Inbox · 1440`.
Pulled forward from stage W at his request; the build waits for its place in the stage order unless he asks.
**Claim:** `36d90015fdd6` (`classic-pen-inbox`), branch `claude/inbox-design`, folder `.worktrees/inbox-design`.

**Pencil:** `Communications · Inbox · 1440` in `classic.pen` (x 3080, y 5790), committed on main `6ecd56fe`.
Light theme; dark checked by switching the frame's theme.

**Concept:** three separate cards (list 320 · conversation · customer 344), slim sidebar as on Schedule, no page
title (Jafar's 2026-08-25 choice), chat-style timeline. Jafar asked whether it was new; the honest answer was
an improvement of the live three-column layout, and he chose to keep it. Live behaviour came from
`src/routes/(app)/communications/+page.svelte` and `src/lib/components/communications/*`.

**Additions:** Jafar allowed new and removed elements for this screen ("you can add remove button, introduce
new element"). The approved list lives in the plan § Approved additions → Unified inbox additions. Channel
colours (Email blue, text green, website chat teal) are in the recipe § Colour rule.

**Drawn state:** text-reply composer (no subject, segment estimate, single Send). Not yet drawn: the email
composer (subject, templates, Send later), empty, loading, error, needs-review, chat-ended and no-permission
states.

**Next:** draw those states in one `Communications · Inbox · states` frame in a later session, then plan the
build against the unified inbox contract. Branch `claude/inbox-design` is **Waiting to merge**: main has another
writer's uncommitted edits, so it merges once main is clean.

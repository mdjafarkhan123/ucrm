# `Last communication` rail card on the client page

- **Priority:** P2


- **Campaign:** `clients-properties`, but the work belongs to `communications`.
- **Reason:** Jafar deferred it on 2026-08-17 when the client Details/Communication tabs were built. There
  are no messages to summarise yet, so the card would only ever be empty.
- **What it is:** Jobber's client detail rail carries a `Last communication` card under Tags — date and
  time, the subject, a `Read more...` link, and a chevron opening the full history. Toured live and written
  up in `.claude/skills/jobber/jobber-01-clients-properties.md` §2.4. We have no equivalent.
- **Reactivation trigger:** The Communications campaign lands a real message history on the client's
  Communication tab.
- **Prerequisites:** The shared Conversations model exists and the Communication tab lists real messages.
- **Checkpoint:** `src/routes/(app)/clients/[id]/+page.svelte`, the `rail()` snippet.


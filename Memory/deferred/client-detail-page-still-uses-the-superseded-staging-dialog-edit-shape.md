# Client detail page still uses the superseded staging-dialog edit shape

- **Priority:** P2


- **Campaign:** `clients-properties` (closed), reopened as a debt by Jafar's 2026-08-18 rule change.
- **Reason:** Client detail was built to the 2026-08-17 rule where a block's pencil opened a dialog that
  staged into `DetailEditBar`, and `/clients/[id]/edit` was deleted. On 2026-08-18 Jafar adopted all three
  of Jobber's edit patterns instead. He chose to convert clients as we next touch that page rather than
  stopping Requests to do it.
- **Reactivation trigger:** Any work that opens `src/routes/(app)/clients/[id]/+page.svelte`.
- **Prerequisites:** Blocks edit in place with their own scrolling Cancel/Save that writes immediately; the
  bar keeps only tags, notes, pins and staged deletes; restore the full edit page reached from the client
  card's `...` menu in a new tab. See `.claude/skills/jobber/jobber-08-screen-patterns.md` § How WE compare.
- **Checkpoint:** `src/routes/(app)/clients/[id]/+page.svelte`,
  `src/lib/components/clients/ClientDetailsDialog.svelte`.


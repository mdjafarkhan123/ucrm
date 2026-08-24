# A customer file re-resolves the whole quote document

- **Priority:** P2


- **Campaign:** `quotes` Part 5B1 — found 2026-08-21 during the API performance review of the customer link.
- **Reason:** `/q/[token]/files/[attachmentId]` authorizes a file by calling `resolve_quote_access_link` and
  checking the id against the document it returns. That is correct and leaks nothing, but it assembles the
  full document — every line, package, attachment and total — once per file. A customer copy with ten line
  photos costs eleven document builds per view instead of one. Customer views are rare next to staff traffic,
  so this is a shape worth fixing, not a live problem.
- **The likely fix:** a second service-role-only function, `resolve_quote_access_file(token_hash, attachment_id)`,
  that does the same one indexed token lookup and returns only the object key, mime type and file name for a
  file the link's version actually names. Same seam, no JSON assembly. A short-lived in-process cache keyed by
  token hash is the cheaper alternative but weakens instant revocation.
- **Reactivation trigger:** customer documents routinely carrying several line photos, or the first measured
  slowness on the customer page.
- **Checkpoint:** `src/routes/(public)/q/[token]/files/[attachmentId]/+server.ts`,
  `supabase/migrations/20260821170000_quote_customer_access_links.sql`.


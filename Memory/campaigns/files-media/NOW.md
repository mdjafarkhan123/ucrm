# Files and Media — now

**Goal:** One contractor File Manager backed by private R2, with one File linked to every CRM use.

**Done:** Parts 1–6D closed. Part 6E (messages reuse) built 2026-09-23, migration `20260923190000`
pushed live, `npm run check` clean — full detail in ROADMAP.md's Part 6E row.

**Exact next action:** Browser-verify Part 6E as Raad LTD office login: open a client's conversation, use
the new "Attach files from Files" button (next to the paperclip) to pick an existing library File on an
email reply, send it, confirm the recipient side / delivery-intent got the real attachment, then open that
File's details panel and confirm "Used in" lists the message and links to `/communications?client=...`.
Repeat once for SMS (1-file cap). No pgTAP file exists yet for this migration — write one, or at least run
`supabase test db` to confirm the touched functions (`file_usage`, `can_view_linked_entity`,
`can_manage_linked_record`, `linked_entity_exists`) didn't regress an existing test.

**Blocker (campaign-wide):** the upload worker does not run locally; new uploads stay "Still being checked" —
irrelevant to 6E, which only reuses already-available Files.

**Deferred, not this part:** `ManualEmailDialog` (new-conversation compose) was not given the library
picker — only the existing-conversation reply composer was. Revisit if Jafar wants it there too.

**Not yet selected after 6E verification:** 6F (marketing asset upload), Part 7 (customer publication/proof
of work), Part 8 (trash/export/security/scale). Ask Jafar which to build next.

**Pointers:** `docs/files-media-behavior-contract.md`, `Design/Files and Media/README.md`.

# Part 6 — Delete and restore a customer

**Plan:** `docs/data-privacy-deletion-behavior-contract.md` § Deleting a customer. **Design (read first):**
`docs/data-privacy-client-delete-restore.md`. **Look:** `modals.md` § Delete client pop-ups (`WEpOG`),
`layout.md` § Recently deleted page (`Wf0tP`).
**Branch:** `claude/data-privacy-part6`, worktree `.worktrees/data-privacy-part6`, reservation `249e82c7c211`.

## Slices

- **6a Database** — `client_deletions`, `client_deleted_at` marks, policies, write guard, contact index, send and
  marketing gates, inbound match, `delete_clients`, `client_delete_preview`, `restore_client_deletions`,
  `recently_deleted_clients`; pgTAP. **Done 2026-10-24:** migration `20270110090000` applied to dev; pgTAP
  `client_delete_restore.sql` 44/44; `client_permanent_delete` 66/66, `organization_purge` 42/42 and
  `communications_sms_inbound_media` 9/9 still pass. `client_create_edit.sql` fails 7 of 21 with or without this
  migration (`mark_property_for_geocoding`: permission denied for schema private) — older problem, not raised yet.
  Same-phone restore: the clashing value stays hidden on the restored client (its message history points at it);
  merge moves that history onto the newer client's value first.
- **6b Read sweep — done 2026-10-24.** `20270110091000`: 41 definer lists/reports/customer links read filtered
  work tables (47 related pgTAP files: same results before and after). `20270110092000`: forwards marked, Messenger
  reply claim cancels. Inbox (`email-history`) and conversation search filter the mark. Messenger inbound already
  starts a new lead for a deleted client (`record_communication_messenger_inbound_message`); after restore the
  Messenger identity stays with that new lead. **Open:** Files page still lists a deleted client's files
  (`list_files` shows every file to `files.view`); invoices whose client is hidden must show "Deleted client" (6d).
- **6c Day 30 — done 2026-10-24.** `20270110093000` (job now `client-deletion-hourly`), `client-deletion-scheduled.ts`,
  vitest 12/12 (privacy folder), pgTAP 48/48. Types added by hand to `database.types.ts` (regenerating from dev would
  drop other branches' tables).
- **6d API and screens — built 2026-10-24.** Routes `/api/clients/delete` (GET preview, POST delete),
  `/api/clients/deleted` (list), `/api/clients/deleted/restore`; `ClientDeleteDialog.svelte` (one or many, money-open
  refusal, counting and failed states, Undo toast); client page ⋯ → Delete client; Clients list row menu Delete,
  bulk-bar Delete (was a disabled placeholder), More → Recently deleted; page `/clients/deleted` with rings, pills,
  pick bar and the same-phone pop-up. Live on this branch's dev server (port 5181), Raad LTD owner: delete →
  hidden from requests, search, client page (404) → listed in Recently Deleted → Restore → all back. Light and dark
  at 1440 checked; fixed a double line under the card heading. Test client "Privacy Test" (Raad LTD) left in
  Recently Deleted on purpose so day 30 (2026-11-23) runs on a real row.
- **6e Proof — open.** Side-by-side with Pencil `ih9b2` and `WEpOG` (Pencil had another file open); live checks of
  the money-open refusal and same-phone pop-up; Files page gap; invoices of a hidden client show "Deleted client";
  performance verification (design doc § Performance design); merge to main.

## Choices beyond the plan (flag to Jafar)

- "Restore as a separate client" when a newer client has the same phone/email: the newer client keeps the
  phone/email (one business can't hold the same number twice), the restored one comes back without it.

## Next action

6e: compare live with Pencil `ih9b2`/`WEpOG`, check the refusal and same-phone pop-ups live, then the open items
above, performance verification, and merge to main.

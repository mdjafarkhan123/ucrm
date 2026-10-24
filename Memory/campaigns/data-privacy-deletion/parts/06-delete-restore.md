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
- **6b Read sweep** — security-definer lists, boards, reports, schedule (`client_schedule_rows`,
  `schedule_calendar_context`, `job_schedule_stages`), pipeline, financial pages, `ready_to_bill_page`, quote list,
  customer links (quote, job report); server modules reading with the service key (inbox, Files, search,
  automation and review workers). Invoices show "Deleted client" where the client join is now empty.
- **6c Day 30** — hourly job and route, retries, owner alert.
- **6d API and screens** — `/api/clients/delete`, `/api/clients/deleted` (list, restore); Delete client pop-up
  (one and many, money-open refusal, counting/failed states), Undo toast, Clients list bulk action, Recently
  Deleted page with every state, same-phone pop-up.
- **6e Proof** — performance verification (design doc), live delete → restore journey in Chrome, screen check.

## Choices beyond the plan (flag to Jafar)

- "Restore as a separate client" when a newer client has the same phone/email: the newer client keeps the
  phone/email (one business can't hold the same number twice), the restored one comes back without it.

## Next action

6b read sweep. Known gaps: Messenger identities of a deleted client (inbound Messenger would still attach to them),
messenger send claim, inbox (`/api/communications/email-history` reads with the service key), Files page, notes.

# Part 6 — Delete and restore a customer

**Plan:** `docs/data-privacy-deletion-behavior-contract.md` § Deleting a customer. **Design (read first):**
`docs/data-privacy-client-delete-restore.md`. **Look:** `modals.md` § Delete client pop-ups (`WEpOG`),
`layout.md` § Recently deleted page (`Wf0tP`).
**Branch:** `claude/data-privacy-part6`, worktree `.worktrees/data-privacy-part6`, reservation `249e82c7c211`.

## Slices

- **6a Database** — `client_deletions`, `client_deleted_at` marks, policies, write guard, contact index, send and
  marketing gates, inbound match, `delete_clients`, `client_delete_preview`, `restore_client_deletions`,
  `recently_deleted_clients`; pgTAP. Not started.
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

Write migration 6a.

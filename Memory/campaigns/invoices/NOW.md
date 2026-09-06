# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- **Part 5a CLOSED 2026-09-05 — committed `fba33ca`, browser-verified end to end. Awaiting Jafar's pick of the
  next thread.**
- Parts 1–4, 5a, 6a, 6b-1, 6b-2, 6c, 7a closed. 5b/5c are the remaining Job→Invoice handoff work.

## Next action

Ask Jafar which thread to take next; do not auto-start one. Dependency-ready options:

- **5b** — per-visit / billing-period invoicing, Invoice now/later at visit completion, per-line service
  dates, ready-to-bill queue. Needs Jobs 13a (done). This is where the 5a deferrals land (service dates,
  mixed-property splitting stays in Part 8).
- **5c** — Jobs 11c installments (payment schedule, per-visit amounts) + progress invoicing. Needs Jobs 11a.
- **8** — batch create + batch deliver (needs 5–7).

Cleanup debt to flag when picking: several closed parts are verified but **not yet committed to Git** per the
roadmap — 3c, 6c, 7b (and 6b-1a's migration/plumbing). Worth a commit sweep before more building.

## 5a deferrals (decided, not bugs — carry into 5b)

- Per-line **service dates** not copied (shared line editor has no service-date field; index alignment breaks
  on reorder). 5b adds visit selection + a date editor.
- Mixed-property selections are **refused** in the picker (tax rates can differ); splitting belongs to Part 8.
- Applying an existing quote **deposit** at creation is still UI-only to build (`apply_client_payment` exists).

## Carried over (pre-existing, app-wide)

- Not-found records sit on a loading skeleton forever (`/payments/<bad id>`, `/invoices/<bad id>`).
- Raad LTD sender display name is "Staff Jafar"; should be the business name — contractor-side fix in
  Settings → Communications → Email.
- Raad LTD email allowance is a manual Unlimited override, not a package entitlement — proper fix belongs to
  **communications-activation** (Paused).
- Leftover test data on invoice #5 "D2 refusal test": a $1,000 "other" payment + two extra receipt emails to
  `info.hiddenknowledge@gmail.com`. Append-only history — remove only by reversal, with Jafar's OK.
- New this session: invoice **#6** ("Testing job", $66,500, Raad LTD) is a verification draft from billing
  Job #1. Delete it if the clean-data matters.

## Notes

- `database.types.ts`: the two 5a RPCs were hand-added; a later regeneration will reorder them — fine.
- Local migration filenames and remote migration versions do not match — existing convention.
- Repo-wide CRLF drift on ~300 `src/` files — unrelated, never stage it. `.env` is CRLF too.
- Skill-dir edits (`.claude/`, `.agents/`, `.codex/`, `.opencode/`) are never staged with feature commits.
- Deferred: payment edit/delete, void→client cancellation email, bulk payment across invoices, Invoices list
  stat cards unwired.

Resume command: `read memory and continue the Invoices campaign`.

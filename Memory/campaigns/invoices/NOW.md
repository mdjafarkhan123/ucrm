# Invoices: Current Checkpoint

- Goal: Jobber-grounded invoicing and manual collection.
- Parts 1–4, 5a, 5b-1, 5b-2, 5b-3, 6a, 6b-1, 6b-2, 6c, 7a closed. **5b-3 CLOSED and COMMITTED
  2026-09-06 (`37d3992`), together with the reminder-resolution fix that also backfixes 5b-2.**
- The partial-billing reminder bug is fixed and covered: `create_invoice_from_work` now resolves only
  the reminders its claims answered. 17 pgTAP assertions in
  `supabase/tests/database/invoice_reminder_resolution_scoped_to_billed_work.sql`, all passing.

## Next action

Pick the next Job→Invoice handoff part with Jafar: **5b-4, 5b-5, or 5c** (read `ROADMAP.md` to select).
Nothing is blocked.

## Open items Jafar has not decided

- Job #2's Sep-30 and Oct-31 month-end reminders are still marked `resolved/invoiced` with no invoice
  behind them — damage the old bug did before the fix, on test data only. Offered to reset; awaiting
  Jafar's word. Nov-30 is correctly pending.
- Direct page loads of `/jobs/<id>` blanked with a Svelte hydration error
  (`Cannot read properties of undefined (reading 'call')` inside Vite's optimized deps) while
  in-app navigation to the same page worked. Looks like dev-server dep-cache state, not this work —
  no frontend file changed this session. Worth a `rm -rf node_modules/.vite` + restart if it recurs.

## 5a deferrals (decided, not bugs — carry into later 5b/8 parts)

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
- Verification drafts nobody needs: invoice **#6** ($66,500, Job #1), **#7** ($150, 5b-1), **#8** ($75,
  5b-2 visit), **#9** ($75, 5b-3 period), **#10** ($75, the fix's live check). Delete any if clean data matters.
- Job **#2** ("Recurring Lawn Care Test", Tester Account) is the invoicing test job: billing is
  fixed-per-period / month-end, one $75 line, its Sep 8 + Sep 22 visits complete.

## Notes

- `database.types.ts`: the two 5a RPCs were hand-added; a later regeneration will reorder them — fine.
- Local migration filenames and remote migration versions do not match — existing convention.
- Repo-wide CRLF drift on ~300 `src/` files — unrelated, never stage it. `.env` is CRLF too.
- Skill-dir edits (`.claude/`, `.agents/`, `.codex/`, `.opencode/`) are never staged with feature commits.
- The MCP SQL client returns only the last statement's rows; to read a whole pgTAP run against the dev
  project, collect each `is()` into a temp table (granting `authenticated` on it) and select at the end.
- Deferred: payment edit/delete, void→client cancellation email, bulk payment across invoices, Invoices list
  stat cards unwired.

Resume command: `read memory and continue the Invoices campaign`.

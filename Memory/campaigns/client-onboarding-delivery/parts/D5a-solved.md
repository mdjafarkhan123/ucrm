# D5a — Solved, reopen, Uplift starts a chat

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` § 7 "Follow-up"
**Code:** `main`
**Done when:** A solved chat reopens when the member writes and keeps its history; a chat Jafar starts reaches the
chosen member.

## Steps

- [x] Database change `20261006160000_support_solved_and_uplift_starts` applied (recorded under its file
      version), types regenerated
- [x] Server: `PATCH /api/jafar/support/threads/[threadId]/status`, `POST /api/jafar/support/threads`
      (Uplift starts), `GET …/support/organizations/[organizationId]/members`, its `attachments/presign-upload`;
      inbox `status` filter (open by default); `status` in member reads
- [x] Screens written: inbox status filter, Solved tag in rows, Mark solved / Reopen, New chat button and
      pane (`SupportStartChat.svelte`, `?new=pick` or `?new=<org id>`), Message this business on the org page,
      Solved tag and "Write again to reopen" in the messenger
- [x] `npm run check` 0 errors, lint clean, existing chat tests pass
- [x] `svelte-autofixer` on `SupportStartChat.svelte` (with its style block stripped — SCSS confuses it)
- [x] Tests: status route, Uplift start route (refuses a non-member, retry makes no second chat), members
      route, inbox status filter
- [x] Database checks with `execute_sql`: writing in a solved chat reopens it; same client id → one chat
- [ ] Browser run: mark solved → contractor sees Solved → contractor writes → open again in inbox; New chat
      from inbox and from org page reaches the chosen member; phone width

## Next

Browser run (last step). Not yet seen in a browser at all.

## Outside actions

- Apply migration `20261006160000_support_solved_and_uplift_starts` — done 2026-10-03; check: `select version from
  supabase_migrations.schema_migrations where version like '20261006160000%'` or column
  `support_threads.status` exists

## Notes

Writing reopens quietly, with no grey line; Uplift's own Solved/Reopen leave one. An Uplift-started chat belongs to
the chosen member (`started_by_user_id`), with `opened_by = 'uplift'`.

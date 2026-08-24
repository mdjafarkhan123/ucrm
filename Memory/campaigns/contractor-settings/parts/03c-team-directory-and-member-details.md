# Part 3C: Team Directory and Member Details

## Outcome

Owners and Administrators can open Team from Settings, find Pending, Active, and Deactivated people, inspect
one person's business details, and deliberately save supported profile changes without entering the later
Roles & permissions or offboarding work.

## Approved boundary

- Add Team and Roles & permissions destinations to the Settings home only for users authorized to manage Team.
- Team is live in this slice. Roles & permissions may be visible as the approved destination but remains clearly
  unavailable until 3D; it must not expose raw permission keys or working edit controls.
- The Team directory includes search, a status filter, status-separated results, seat usage, and a deliberate
  Invite member entry point backed by the shipped 3B invitation route.
- A member detail view shows Member details and a read-only Role & access summary. Availability is omitted until
  Scheduling exists.
- Member details may save display name, work phone, job title, and scheduling color through the shipped
  `update_team_member_profile` command with `profile_revision` conflict protection.
- Pending members show their invitation state, including a durable Delivery failed label in both the directory
  and detail screen, plus the shipped resend, cancel, and replace-email actions. These actions require an
  explicit confirmation or Save-labelled action and precise query invalidation.
- Role changes, permission adjustments, deactivation, restoration, removal, and ownership transfer are outside
  this slice even though their database commands already exist.

## Implementation split

## Progress

- [x] Database read seam: `list_team_directory`, tenant authority, search, state filter, seat count, and cursor.
- [x] Database verification: 20 pgTAP assertions, live query plan, security/performance advisors.
- [x] Bounded `/api/team/members` contract and seven focused route tests.
- [x] Typed TanStack Query ownership and Settings navigation.
- [x] Team directory UI (code complete; browser verification pending).
- [x] Read-first member-details implementation: protected exact-member read, profile save route, TanStack
      detail cache, directory links, conflict recovery, and focused API coverage. Browser verification remains.
- [x] Pending invitation interactions. Resend, cancel, and replace-email were already implemented (routes,
      dialogs, cache invalidation) from earlier uncommitted work; this session added the one missing piece —
      a durable "Delivery failed" badge in both the directory status cell and the member-detail rail, reading
      the existing `invitation.delivery_failed` field. Browser-verified 2026-08-24 end-to-end with a real
      invitation to a Jafar-controlled test address: invite, resend, delivery-failed badge (forced via a
      temporary, reverted SQL flip to confirm rendering), change-email dialog, and cancel. Cancel correctly
      leaves the member row `pending` until the 5-minute `team-invitation-maintenance-five-minutes` pg_cron
      worker reconciles it (confirmed working against the live Vault-configured worker URL) — this is the
      intended async design from Part 3B, not a bug.
- [x] Final browser completion gate accepted by Jafar on 2026-08-24; all exercised checks passed. Performance
      gates passed for the database, API, and client layers.

### 1. Read model and contracts

- Replace the current unbounded `/api/team/members` access-editor payload with a focused directory response.
- Validate `search`, `status`, `limit`, and cursor inputs; cap the page size and use keyset pagination.
- Return only the directory/detail fields needed now: stable identity, display name or invited email, role,
  membership/invitation state, business contact fields, revisions, joined/invited dates, and seat summary.
- Keep the detailed permission map out of the directory payload. A later 3D endpoint owns that heavier model.
- Join or batch profiles and invitation state without per-member Auth Admin calls or N+1 database reads.
- Use private authenticated cache headers and preserve `requireContractorTeamAdmin` at every Team route.
- Add route tests for validation, authorization, tenant scoping, cursor behavior, state/search filtering, payload
  minimization, and database failure handling.

### 2. Client data ownership and Settings navigation

- Add one typed Team API module with stable TanStack Query keys for list filters and individual members.
- Use a short deliberate stale time, infinite-query cursor loading, cached rows for member-detail placeholder
  data, and exact invalidation after invitation/profile actions.
- Add the Team & access group to Settings only when the settings response says the actor may manage Team.
- Warm the routinely used Team routes in the app layout and use links so hover preloading works.

### 3. Team directory UI

- Reuse `PageContainer`, `PageHeader`, `SearchInput`, `FilterBar`, `FilterField`, `Select`, `DataTable`,
  `ListLoadMore`, `Avatar`, status badges, skeletons, empty states, errors, and the shared Button.
- Show a compact desktop table and a usable narrow-screen presentation without duplicating the data source.
- Make member names real links, keep rows keyboard-safe, announce status in text, and preserve focus while
  filtering or loading another cursor page.
- Keep Pending, Active, and Deactivated understandable through the status filter and visible labels. Removed
  tombstones are historical records and do not appear in the management directory.

### 4. Member details and invitation interactions

- Build a read-first member details page with independently owned Member details and Role & access sections.
- Member details edits in place and writes only when Save is pressed; Cancel restores the server value.
- On a 409 revision conflict, keep the user's draft, explain that another manager changed the record, and offer
  a fresh reload rather than overwriting.
- Keep Role & access read-only with a plain explanation that editing arrives in Roles & permissions (3D).
- Put resend/cancel/replace-email controls only on Pending members and reuse accessible shared dialog controls
  for confirmations/forms.
- Do not add availability, access-activity history, destructive lifecycle actions, or role/permission controls.

### 5. Verification and browser gate

- Run focused route/component tests, Svelte autofixer on every touched Svelte file, Prettier on touched paths,
  `npm run check`, relevant unit tests, and a production build.
- Run the performance gate for the API query, TanStack keys, pagination, list rendering, and route chunks.
- Browser-verify as Owner/Administrator on desktop and 390px mobile: Settings visibility, loading/skeleton,
  search, each status, load-more, member navigation, successful detail save/cancel, conflict recovery, Pending
  invitation actions, keyboard order, focus return, and unauthorized direct API/page denial.

## Risks and decisions already made

- The current `/api/team/members` mixes directory data with the future permission editor and is unbounded. Do
  not carry that response shape into the UI.
- Auth email must not be fetched once per member. Pending email comes from the invitation record; an active
  member's sign-in email may require a bounded server-side batch or omission if Supabase cannot supply it safely.
- Search across profile and invitation tables can defeat keyset pagination if performed as two independent
  lists. Keep one deterministic server ordering and cursor contract; do not merge independently paginated
  browser results.
- The worktree contains protected Quotes, Pipeline, and earlier Settings changes. Touch only the 3C files and
  the narrow shared navigation/warm-route lines required by this packet.
- No migration is planned. If inspection proves an index or read seam is missing, stop before SQL, load the
  Postgres skill, and present the schema change for approval.

## Completion gate

Authorized users can find and inspect members across Pending, Active, and Deactivated states; supported member
details save with independent conflict protection; unauthorized roles cannot see or call Team management; and
navigation renders cached or skeleton state without blocking. Desktop/mobile and accessibility checks pass,
and the changed API/TanStack/Svelte path passes the performance review.

## Browser verification

Jafar confirmed on 2026-08-24 that the remaining live browser checks passed. Cursor loading remains
route-tested only because no extra test members were authorized. Pending-member resend, cancel,
replace-email, and the delivery-failed badge were browser-verified on 2026-08-24 (desktop). Jafar waived the
390px mobile pass the same day — desktop verification is accepted as sufficient for this slice; Part 3C is
closed.

## Source pointers

- `docs/contractor-settings-blueprint.md` → **2. Team & access** and **Confirmed Part 3 behavior**.
- `Memory/campaigns/contractor-settings/parts/03-team-and-access.md` → 3C scope and completion gate.
- `Memory/campaigns/contractor-settings/parts/03a-access-and-data-foundation.md` → shipped command boundaries.
- `src/routes/api/team/members/+server.ts` and `src/routes/api/team/invitations/*` → current read/action routes.
- `src/lib/server/access/team-commands.ts` → the one write road for membership/profile commands.
- `.claude/skills/jobber/jobber-08-screen-patterns.md` → shared list and read-first editing behavior.

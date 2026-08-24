# Part 1 — Settings Foundation and Business Profile

## Outcome

Deliver the trustworthy foundation every later contractor setting uses: the Settings directory, shared
business identity and branding, operational formatting defaults, business hours, personal Account/Security
entry, and matching authorization.

## Approved behavior

- One Settings page shows seven bordered category sections and all currently usable destinations directly.
- A sticky category jump bar scrolls within that page and highlights the visible section.
- Destination cards use icon, simple name, short description, optional truthful status, and an open affordance.
- Responsive grid: four columns on wide desktop, three on desktop, two on tablet, one on mobile.
- The current person's name, role, and Account/Security shortcut sit above the organization sections.
- Business Profile owns business name, trade, main phone, website, description/tagline, address, operational
  timezone, and currency.
- Branding owns logo and customer-facing brand color; it does not alter the CRM theme.
- Business Hours owns the weekly shared default and its configured state.
- Only working, permitted destinations appear. There are no placeholder category pages.
- Nothing writes until Save; Cancel restores saved values.
- Default changes never rewrite customer-visible history.
- `docs/contractor-settings-blueprint.md` **Confirmed Part 1 behavior** wins over any older assumption.

## Reconciliation corrections confirmed 2026-08-22

1. Business Profile completeness needs only customer-facing business name, confirmed operational timezone,
   and confirmed currency. Trade, phone, website, description, and address stay optional.
2. New organizations start `not_configured`. Mon–Fri 8–5 may be an unsaved UI suggestion only. Existing
   seeded rows are preserved, but the mode stays unconfirmed until an owner/admin saves.
3. 24-hour operation is an explicit state, never a `00:00`–`00:00` magic value.
4. Keep existing and replaced logo objects for now. Once documents reference frozen logos, retain every
   referenced object and delete only unreferenced uploads after a grace period. No permanent-retention promise.
5. The dirty Quotes worktree is untouched here. Frozen document branding is a blocking Quotes-owned
   integration; Part 1 is not fully complete until an approved customer surface proves it.
6. Customer logo access resolves through a valid customer document/access token. Part 1 prepares the server
   capability only; no generally public organization-logo endpoint.
7. Currency locks when a Quote has `current_published_version_id` or has been sent/shared. Drafts never lock.
8. `address_is_public` defaults off: customer surfaces then show only city and state/region; on shows full.

## Layer 1 — Database: done 2026-08-22

`supabase/migrations/20260824090000_contractor_settings_reconciliation.sql`, applied. Three revision
counters and three editor stamps replace the single `revision`; `timezone_confirmed_at`,
`currency_confirmed_at`, `address_is_public`, and `hours_mode` added; hours re-keyed on
`(organization_id, weekday, period_index)` with `is_open_24h` and a three-shape check that allows an
overnight period; the seeding trigger dropped so a new organization starts genuinely unconfigured;
`organization_settings_audit` added; the single save command replaced by
`save_organization_business_profile` / `save_organization_business_hours` / `save_organization_branding`,
each returning `{ status: 'stale', editor_name, edited_at }` instead of raising on a conflict; the currency
lock moved to `current_published_version_id is not null or sent_at is not null`.

Proof: `supabase/tests/database/contractor_settings_business.sql`, 33 assertions, all passing against the
remote project inside a rolled-back transaction. One caught a real gap — confirming a suggested timezone or
currency wrote no history row — fixed by recording `timezone_confirmed`/`currency_confirmed` as changes.
`performance-review` passed; three editor foreign-key indexes were added because the advisor flagged them.

## Layer 2 — API: done 2026-08-22

- `GET /api/settings` — Settings home: member, edit permission, and honest per-card readiness.
- `GET /api/settings/business` — one read for all three pages, each with its own revision and last editor.
- `PATCH /api/settings/business/profile`, `.../business/hours`, `PATCH /api/settings/branding` — one section
  each, one revision each, 409 naming the other editor.
- Logo routes keep the replaced object (retention until documents freeze branding) and are now rate-limited.
- `src/lib/server/settings/logo.ts` holds the safe streaming the token-scoped customer route will reuse.
- A profile save clears the tenant-global formatting cache; without it a new timezone or currency took up to
  five minutes to reach the rest of the app.

Proof: 42 tests in `src/routes/api/settings/settings-business.spec.ts`; `npm run check` clean; full unit
suite 888 passing. `performance-review` passed.

Shapes Layer 3 needs: the read returns `profile`, `branding`, `hours` (mode + periods), `readiness`, and
`currency_locked`. Saves send only their own section plus `expected_revision`. Timezone and currency need
`confirm_timezone` / `confirm_currency` — the database refuses to change either without them.

## Layer 3 — done 2026-08-22

Settings directory (`/settings`) and Business Profile / Branding / Business Hours pages
(`src/routes/(app)/settings/**`), each on `RecordFormLayout` + `SectionBlock` with the person's own even
50/50 two-column split (see `feedback_two_column_even_split_layout.md`) rather than a narrow rail. Each page
saves independently against its own `expected_revision`, surfaces a 409 as a named-editor conflict banner
(never a blind overwrite), and warns before leaving a dirty page (`beforeNavigate` + `beforeunload`).
Business Hours offers the not-configured empty state (Mon–Fri suggestion / custom / by-appointment) per the
Part 1 corrections. `src/lib/settings/api.ts` holds the fetch/save functions and query keys;
`src/lib/components/settings/SettingsDestinationCard.svelte` is the shared home-page card.
Jafar reviewed the two-column shape live and approved it as the new standard going forward.

## Layer 4 — AppShell identity, breadcrumbs, and desktop browser verification done 2026-08-24

`(app)/+layout.server.ts` also loads `logoUrl` beside `organization`; `AppShell` → `Sidebar`/`MobileNav`
render the org's saved logo and Business Profile name in place of the generic "Contractor CRM" mark (owner
`/jafar` Control Room variant is untouched). Warm routes cover all four settings routes. `Breadcrumbs` is
wired into Business Profile, Branding, and Business Hours (Settings › page name, back to `/settings`).

Live-verified on desktop: sidebar logo/name swap, all four settings pages, Save/Cancel dirty-state, the
currency-lock message, and the not-configured Business Hours empty state. Two bugs found and fixed in the
same session:
- `businessProfileReadiness` (`src/lib/server/settings/readiness.ts`) counted currency as permanently
  missing once it locked (a quote sent) before ever being explicitly confirmed, with no way to confirm a
  disabled field — Business Profile could never show complete. Fixed: a lock now counts the same as a
  confirmation. Both callers (`/api/settings`, `/api/settings/business`) pass `currency_locked` through;
  covered by two new tests in `settings-business.spec.ts`.
- All three save flows (`business-profile`, `branding`, `business-hours` pages) cleared `saving`/dirty
  state before the async `invalidateQueries` refetch had updated `query.data`'s revision, so an edit made
  immediately after a save reused the stale `expected_revision` and got a false "someone else changed
  this" 409. Fixed with a synchronous `queryClient.setQueryData` revision patch on every successful save
  (profile, branding color, logo upload/remove, hours), ahead of the invalidate.

Mobile/390px pass: closed 2026-08-24. `resize_window` still cannot change to a narrow viewport in this
environment, so Jafar checked the four settings pages himself at 390px and confirmed they're fine — no
automated capture was produced.

Deferred: `Memory/deferred/team-member-profile-save-may-have-the-same-stale-revision-race.md` — the Part 3C
Team member profile save may have the identical bug; not touched here since it's outside Part 1.

Run the Postgres, Supabase, Svelte, design, Bits UI where applicable, and performance-review gates per layer.

## Blocking integrations owned elsewhere

- **Quotes:** snapshot organization logo object key and brand color onto the published version, serve them
  through the existing `/q/[token]` access-link path using `src/lib/server/settings/logo.ts`, and prove a
  published document keeps its branding after the logo is replaced. Confirmed still unbuilt 2026-08-24: no
  quote migration snapshots logo/brand color, and the customer-facing `/q/[token]` page renders neither.
  Jafar explicitly deferred this to the Quotes campaign rather than building it inside contractor-settings.
  Trigger: the Quotes campaign resumes. Part 1 stays open only for this one acceptance test.
- **Logo cleanup:** delete only unreferenced uploads after a grace period, once those references exist.
- **Incomplete setup:** blocking belongs to the action that needs the missing truth, delivered with each
  owning feature; Part 1 only reports readiness and links to the exact setting.

## Acceptance checks

- An authorized administrator can discover every usable setting without entering a category submenu.
- Category links land on the correct bordered section and active highlighting follows scrolling.
- Keyboard and mobile users can reach every card and category link without losing context.
- Unauthorized members neither see nor call protected business-setting actions.
- Save, Cancel, validation, failure, and concurrent-edit behavior preserve saved truth and name the conflict.
- Branding appears on an approved customer-facing surface without changing the internal app theme.
- The contractor sidebar shows the saved company name and logo, falls back cleanly, and never flashes another
  organization's identity.
- New records use current defaults while existing published or sent records keep their frozen values.
- Timezone, currency, and business-hour behavior stays correct at boundary, overnight, and 24-hour cases.

## Non-discoverable risks

- The worktree contains extensive active Quote changes; do not reformat or modify them incidentally.
- Currency is consumed when Requests and Quotes are created; mixed currencies have no honest meaning.
- Platform commercial timezone is deliberately separate from contractor operational timezone.
- Logo URLs used by customer documents must be stable application URLs, not expiring storage links.
- Timezone stays a controlled `TimezonePicker` value validated against `pg_timezone_names`; country stays the
  `LocationPicker` ISO code. Neither is free text.

## Source pointers

- `docs/contractor-settings-blueprint.md`, `docs/PRODUCT.md` §22, `docs/build-sequence.md`
- `docs/quote-behavior-contract.md` customer snapshots and currency
- `supabase/migrations/20260823100000_contractor_settings_foundation.sql` and `20260823110000_...`
- `src/routes/api/settings/`, `src/lib/server/validation/settings.schema.ts`
- `src/routes/(public)/q/[token]/files/[attachmentId]/+server.ts` token-scoped delivery pattern

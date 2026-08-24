# Part 2C: Quote Settings (terms, representative, target margin, signature policy)

## Outcome

Owners and Administrators can configure the four remaining Quote-Settings defaults from
`docs/contractor-settings-blueprint.md` → **Quote settings**: default terms and conditions, an optional
business-representative block, a private target profit margin, and the organization-wide
Require-customer-signature choice. Each saves independently with its own revision protection, matching Taxes
(2A) and Price Book (2B). Quote numbering, presentation, and reusable templates stay out of scope until their
own behavior is approved (per blueprint, no disabled rows/"Coming soon" placeholders for them).

## Approved behavior

- **Terms:** rich-ish text limited to paragraphs, headings, lists, bold, italic, and links — no raw HTML,
  images, tables, scripts, or embeds. Copied into a new Quote draft; changing it never rewrites existing
  drafts or published Quotes.
- **Business representative:** optional block — enabling it requires a name; title and a signature image
  (uploaded or drawn) are optional. Preview shows the customer-facing result; without an image, typed name and
  title still render. Entire block is copied into a new Quote draft as presentation content only — never an
  approval workflow or a list of people allowed to approve.
- **Target margin:** starts **Not set**, never guessed. When set, must be `> 0%` and `< 100%`. Visible only to
  staff with cost/profit permission (existing catalog cost-redaction boundary). Guidance is private and
  informational only — current margin, target, suggested price, required base-Quote margin, and each optional
  add-on's margin shown separately (no Good/Better/Best bundling). Never blocks save/send/approve/convert and
  never auto-adjusts a price.
- **Require customer signature:** organization-wide boolean, starts off. Copied into each new Quote and frozen
  at publish — changing the org setting never changes an already-sent customer link; republishing an existing
  Quote is the only way to apply a newer policy.
- All four sections save independently with separate optimistic-revision protection; a conflict in one never
  blocks another section's valid save. Every successful change records who changed it and when.
- Only Owner/Administrator can view or manage this page, same as Taxes — hidden from every other role, with
  matching server enforcement (new `settings.quotes.manage` permission, not reused from `settings.taxes.manage`
  or `settings.price_book.manage`, matching the one-key-per-Settings-area convention those two established).

## Existing truth to reuse

- `organization_settings` / `organization_settings_audit` already carry the profile/branding/hours/pipeline/
  taxes section pattern: one `<section>_revision`, `<section>_updated_by`, `<section>_updated_at` triple per
  section, a `for update` row lock, a JSON `{status: 'saved'|'stale', ...}` return (never a thrown conflict —
  this is already the non-retried shape, no P0409 migration work needed for new functions), and one audit row
  per successful save. Extend this table; do not create a parallel one. See
  `supabase/migrations/20260902100000_settings_taxes_foundation.sql` for the exact template (permission insert,
  columns, RPC, audit-section constraint).
- `quote_versions.contract_disclaimer` already exists as the free-typed terms box on each Quote version
  (`supabase/migrations/20260820160000_quote_workspace_commands.sql`) with an explicit comment noting "no
  settings-backed default to inherit from yet" — this slice is exactly that missing default. Only the
  Quote-draft creation path needs to read the new default; the frozen per-version column itself is untouched.
- `src/routes/api/settings/branding/logo-upload/+server.ts` already implements the R2 upload boundary for a
  Settings-owned image; the representative signature image reuses that boundary, not a new one.
- The existing `SignaturePad.svelte` (Type/Draw/Clear, touch+mouse, from Quotes Part 5C) already implements
  drawn-signature capture; the representative block reuses it for its own optional signature input rather than
  building a second signature widget. This is a distinct concept from a customer/in-person Quote signature
  (`quote_signatures` table) — no shared table or row, just the shared input component.
- `src/routes/api/settings/business/+server.ts` shows the "one GET assembles every section, one PATCH per
  section" convention this page's API should follow.
- Catalog cost/profit redaction (Price Book, 2B) already has the exact staff-permission boundary target-margin
  visibility must reuse — do not invent a second cost-visibility permission.

## Plan

1. Migration: `settings.quotes.manage` permission (owner+admin); four column groups on `organization_settings`
   (terms; representative enabled/name/title/signature_object_key; target_margin_basis_points with the
   `>0 and <10000` check; require_customer_signature) each with its own revision/updated_by/updated_at; extend
   the `organization_settings_audit` section check to add `'quote_terms'`, `'quote_representative'`,
   `'quote_target_margin'`, `'quote_signature_policy'`; four `set_organization_quote_*` SECURITY DEFINER
   commands mirroring `set_organization_tax_default`'s shape; wire the Quote-draft-creation path to read these
   defaults into a new draft (terms, representative block, signature-required flag) alongside the existing tax
   default. Test tenant isolation, stale-revision paths, permission denial, and that existing drafts/published
   Quotes are untouched by a later default change; run the database performance gate.
2. API: `GET /api/settings/quotes` (one read, four sections, redacts target margin for non-cost-permitted
   staff), four `PATCH /api/settings/quotes/<section>` routes following the Taxes route shape (rate-limited,
   Zod-validated, `settingsWriteError`/`isStale` handling), and a signature-image upload route reusing the
   logo-upload boundary. Add focused route tests; run the API performance gate.
3. Svelte: Settings → Quote Settings page, four independently-saved cards (Terms editor with the restricted
   rich-text toolbar, Representative card with `SignaturePad` reuse and live customer-facing preview, Target
   Margin card gated on cost-permission, Signature-policy toggle), each showing last-editor/time and handling
   its own stale-conflict reload. Defer the page's query until entered per rule 10; targeted cache invalidation
   only for the section written.
4. Run Svelte/design/performance checks and browser-verify: empty state, save/edit each of the four sections
   independently, a stale-conflict on one section while another saves cleanly, permission denial (non-owner/
   admin sees no destination), target-margin redaction for a non-cost-permitted role, representative preview
   with and without a signature image, and that a new Quote draft actually carries the configured defaults
   while an already-existing draft/published Quote does not change.

## Layer 1 (migration) — closed 2026-08-24

Shipped as `supabase/migrations/20260902120000_settings_quote_settings_foundation.sql` plus a same-session
fix `20260902130000_settings_quote_target_margin_own_table.sql`. Terms/representative/signature-policy landed
on `organization_settings` exactly as planned (own revision/updated_by/updated_at triple each, audit-section
extension, `settings.quotes.manage` permission for owner/admin). `quote_versions` gained the four
representative columns plus `require_customer_signature`; `create_quote()` now defaults an untyped disclaimer
from `organization_settings.quote_terms` and copies the representative block and signature-required flag;
`clone_quote_version_to_draft()` carries all five forward from the prior published version, not from Settings
again.

**Real finding caught by this slice's own performance/RLS review, fixed before any API route was built on
top of it:** target margin could not live on `organization_settings` as originally planned. That table's only
SELECT policy is `settings.business.view`, granted to every role including `field` — far broader than Price
Book's `catalog.view` (excludes `field`). Left there, a `field` member could read the target margin straight
over PostgREST, bypassing whatever the API layer redacts. Fixed the same way `organization_tax_rates` already
solved an analogous problem: split target margin into its own `organization_quote_target_margin` table
(organization_id PK, `target_margin_basis_points`, revision/updated_by/updated_at) with its own SELECT policy
(`quotes.view_cost` OR `settings.quotes.manage`) and SECURITY-DEFINER-only writes. Backfilled all existing
organizations and seeded it from the existing `organizations`-insert trigger for future ones.
`set_organization_quote_target_margin` now targets this table instead. `get_advisors` re-checked clean
(security + performance) after the fix.

## Layer 2 (API) — closed 2026-08-24

Routes: `GET /api/settings/quotes` (combined read, all gated on `settings.quotes.manage`),
`PATCH /api/settings/quotes/terms`, `PATCH .../representative`, `POST .../representative/signature-upload`,
`GET .../representative/signature-view`, `PATCH .../target-margin`, `PATCH .../signature-policy`. New server
modules: `$lib/server/settings/quote-terms.ts` (`sanitizeQuoteTerms`, via the new `sanitize-html` dependency —
approved allow-list: p/h2/h3/ul/ol/li/strong/b/em/i/a/br, href schemes restricted to http/https, `rel=noopener
noreferrer` forced) and `$lib/server/settings/quote-representative-signature.ts` (stream/store/discard,
mirroring `$lib/server/settings/logo.ts` and the existing Quote-signature decode primitives). New Zod schemas
in `settings.schema.ts`: `quoteTermsSchema`, `quoteRepresentativeSchema`, `quoteTargetMarginSchema`,
`quoteSignaturePolicySchema`, `quoteRepresentativeSignatureUploadSchema`.

Regenerated `src/lib/database.types.ts` after the migration (it goes stale the moment a migration lands — that
was the whole cause of an 18-error `GenericStringError` typecheck failure before the regenerate). Separately,
a multi-line `.select()` string built with `+` concatenation collapsed TypeScript's literal-type inference for
the same reason and needed to become one plain string literal, matching every existing settings GET route.

**Real finding caught and fixed during this layer's own review:** the representative PATCH route was
spreading the RPC's raw JSON result into its HTTP response, leaking internal R2 object keys (including an
orphaned `previous_signature_object_key` with zero client use) — reshaped to return only
`revision/enabled/name/title/signature_url`, matching how the logo route never returns its raw object key
either.

**Scope note for Layer 3 and beyond:** the representative signature's Settings-page view route
(`.../signature-view`) is deliberately gated on `settings.quotes.manage` — it only serves the Settings page's
own preview. Actually rendering the representative block (name/title/signature image) and the
Require-customer-signature policy into the live Quote editor and the customer-facing document renderer
(`CustomerQuoteDocument.svelte` and the staff Quote detail view) is **not** part of this migration/API slice —
the columns exist and are correctly frozen per version, but no consumer reads them yet. This mirrors Taxes
(2A), where the schema/default-resolution shipped first and the Quote UI's own tax-display reconciliation
(`QuoteTaxCard.svelte`) was a separate, explicitly later slice. Propose that Quote-document-rendering slice
separately once the Settings page itself is shipped and browser-verified.

## Layer 3 (Svelte) — code complete 2026-08-24, partially browser-verified

Shipped: `src/routes/(app)/settings/quotes/+page.svelte` (four independently-saved `SectionBlock` cards,
matching Taxes' page shell rather than `RecordFormLayout` since there is no single combined save — this is
the first Settings page with more than one independent save unit on one page), plus two new reusable
components — `src/lib/components/settings/QuoteTermsEditor.svelte` (hand-built contenteditable rich-text
editor: paragraphs/headings/lists/bold/italic/links only, via `document.execCommand`, no new npm dependency;
an inline URL box replaces `window.prompt` for the Link tool since a native prompt would block the app the
same way it blocks browser automation) and `RepresentativeSignatureInput.svelte` (Upload/Draw segmented
capture; Draw reuses `SignaturePad`'s canvas pointer mechanics without its typed-name mode). Client API
additions in `$lib/settings/api.ts` (`fetchSettingsQuotes` + 4 save functions + upload helper). Wired into
navigation: `quotes_manage` added to `GET /api/settings`'s permissions and `SettingsHome` type, a destination
card added to the Settings home page gated on it, and the route added to the hover-prefetch warm list in
`src/routes/(app)/+layout.svelte`.

**Real finding caught and fixed before any UI was built on top of it:** the already-closed Layer 2
representative PATCH route had no way to keep an existing signature unchanged on a name/title-only edit —
`GET /api/settings/quotes` deliberately never sends the raw storage key to the browser (Layer 2's own
redaction fix), so a save that touched only name/title would silently null out a saved signature every time.
Fixed at the route layer only (no migration, no RPC change): `quoteRepresentativeSchema` gained an explicit
`remove_signature` boolean as the third mutually-exclusive signature input, and the PATCH route now re-reads
the current `quote_representative_signature_object_key` from `organization_settings` and resends it unchanged
whenever the caller supplies none of the three signature signals. Performance-reviewed (one extra indexed
PK read, gated behind the rare branch, on an already rate-limited owner/admin-only path) — ✅ pass. Confirmed
fixed by browser-verifying a name-only edit against a real drawn signature: the signature survived both the
save and a full page reload.

**Browser-verified (2026-08-24, real Supabase, owner role):** Terms — typing, Bold, a link applied via the
inline URL box (not `window.prompt`), Save, last-editor line, and persistence across a full reload.
Representative — toggle on, Name/Title, drawing a signature on the canvas, Save, persistence across reload,
then the critical name-only-edit-keeps-signature fix confirmed via reload. Target Margin — visible (current
role has `quotes.view_cost`), typed a percent, Save, last-editor line. Signature Policy — toggle, Save,
last-editor line. All four cards confirmed to save and reload independently with correct toasts.

**Second browser-verification pass (2026-08-24, same session, owner role):** Representative
Upload-mode (real file picker via `file_upload`, not Draw) — saved and confirmed persisted across a
full reload. Stale-conflict cross-card behavior — two real tabs: Tab B saved Terms first, Tab A (holding
the older revision) got the "Jafar Khan just changed this" banner and a disabled Save on Terms, while
Target Margin saved cleanly in the same tab in the same visit, confirming a conflict on one card never
blocks another. Representative-off state — toggled off, saved, reloaded: Name/Title/signature fields
stay hidden and nothing is lost when toggled back on. Terms empty state — confirmed and fixed (see
below). Mobile 390px pass — waived by Jafar 2026-08-24, matching the 2A/2B/3C precedent (the
`resize_window` tool still no-ops in this environment).

**Two real bugs found and fixed this pass:**
1. `GET /api/settings/quotes` (`src/routes/api/settings/quotes/+server.ts`) always included
   `target_margin.basis_points` (and `last_editor`) whenever the DB row existed, gated only on the
   route-wide `settings.quotes.manage` check — never on `quotes.view_cost`, despite a comment claiming
   otherwise. Because permissions are individually overridable per member
   (`organization_member_permission_overrides`, confirmed in `src/lib/server/access/effective.ts`),
   `settings.quotes.manage` does not imply `quotes.view_cost` — a member could plausibly hold one
   without the other. Fixed by gating both fields on `hasPermission(check.access, 'quotes.view_cost')`,
   matching the boundary `catalog-items` already uses. Performance-reviewed: pure in-memory boolean
   check, no new query. ✅ pass.
2. `QuoteTermsEditor`'s contenteditable leaves a lone `<br>` after "select all, delete" — an ordinary
   way to clear the field — and `br` is in the sanitizer's allow list, so `sanitizeQuoteTerms()`
   (`src/lib/server/settings/quote-terms.ts`) previously saved and returned `"<br>"` as if it were real
   content: the CSS `:empty::before` placeholder never showed, and a new Quote draft would have
   inherited a meaningless `<br>` as its default terms. Fixed by collapsing a sanitized value with no
   content besides `<br>`/`&nbsp;` down to `''`/`null`. Verified live via a direct
   `PATCH /api/settings/quotes/terms` call and a reload: placeholder now renders correctly
   ("No terms and conditions yet…"). Performance-reviewed: one extra regex pass on an already-computed
   string. ✅ pass.

**Third browser-verification pass (2026-08-24, fresh session) — the two blocked checks, both passed:**
1. **Permission denial**, logged in as the real `field` test member (`dev.jafarkhan@gmail.com`,
   Field role): Settings home shows only the "Business" category — no Taxes/Price Book/Quote Settings
   destination card. Direct navigation to `/settings/quotes` confirmed `GET /api/settings/quotes` returns
   403 (checked via network inspection) — no data reaches the browser. The page itself hangs on a blank/
   skeleton loading state rather than showing an explicit error; confirmed this is pre-existing shared
   behavior across Settings pages (Taxes does the same, Price Book eventually shows a generic error after
   retries) and not something 2C introduced — logged as
   `Memory/deferred/settings-quotes-and-taxes-pages-never-resolve-a-403-into-an-error-state.md` (P3, out of
   this part's scope).
2. **Target-margin redaction**, via Jafar's approved temporary override: unchecked `quotes.view_cost` on
   the Admin test member (Jafar Admin) through Team → Roles & permissions → Manage access → Adjust access
   (the individual-access editor does not expose `settings.quotes.manage` as a toggle — it's implicit to
   the Owner/Admin role — but does expose `quotes.view_cost`, which is exactly the boundary being tested).
   Logged in as that Admin: the Quote Settings page loaded normally (Terms, Representative, Signature
   Policy cards all present) but the **Target Margin card was completely absent** — the page goes straight
   from Representative to Signature Policy. Confirmed at the data layer too: `GET /api/settings/quotes`
   returned `permissions: {manage: true, view_cost: false}` and a `target_margin` object containing only
   `revision`/`last_editor` — no `basis_points` field at all. Reverted the override immediately after
   (Admin cannot self-edit access — "People cannot change their own role or access" — so this needed the
   Owner account); confirmed the "Adjusted" badge is gone and the role reads plain "Administrator" again.

Both checks pass. Part 2C's completion gate is now fully met.

## Non-discoverable risks

- Target margin must never appear in any payload sent to a role without cost/profit permission — this is the
  same leak class Price Book's cost redaction already had to solve; reuse its exact boundary rather than
  re-deriving one.
- The representative "signature" here is presentation content copied into a draft, not a legal e-signature and
  not the `quote_signatures` table from Quotes Part 5C. Keep the two concepts and their storage completely
  separate so a future change to one never silently touches the other.
- Because Require-customer-signature is copied and frozen at publish (like tax and terms), the Quote publish
  path — not just draft creation — needs confirming: does `publish_quote()` need to snapshot this flag onto
  the version the same way it already snapshots tax, or does draft-creation-time copy already suffice? Resolve
  from the existing publish function before writing the migration, don't assume.
- Terms formatting is allow-listed (paragraphs/headings/lists/bold/italic/links only). Reuse whatever
  sanitizer/allow-list approach already exists in the codebase if one does; do not add a new HTML sanitizer
  dependency without checking first.

## Completion gate status (2026-08-24) — CLOSED

Every item in the completion gate below is met: permission denial and target-margin redaction were both
browser-verified in the third pass above. The mobile 390px pass remains waived (Jafar, matching 2A/2B/3C
precedent). Part 2C is closed.

## Completion gate

Owners/Administrators can safely configure and independently save all four Quote Settings sections; every
other role has no visibility into the page or its data (including target margin, which stays hidden from any
staff member without cost/profit permission); new Quote drafts pick up the configured defaults without
rewriting any existing draft or published Quote; stale-revision and permission paths are tested; and database,
API, Svelte, browser, and performance gates all pass.

## Source pointers

- `docs/contractor-settings-blueprint.md` → **Quote settings**
- `supabase/migrations/20260902100000_settings_taxes_foundation.sql` → section/permission/RPC template to mirror
- `supabase/migrations/20260820160000_quote_workspace_commands.sql` → `quote_versions.contract_disclaimer`
- `supabase/migrations/20260824072747_settings_price_book_foundation.sql` → cost/profit redaction boundary,
  per-area permission-key convention
- `src/routes/api/settings/business/+server.ts`, `src/routes/api/settings/taxes/default/+server.ts` → API shape
- `src/routes/api/settings/branding/logo-upload/+server.ts` → image-upload boundary to reuse
- `Memory/campaigns/quotes/parts/05c-signatures.md` → `SignaturePad.svelte`, and why it is a distinct concept
  from this settings-level representative signature

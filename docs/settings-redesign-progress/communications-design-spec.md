# Communications settings pages — approved design spec (from Pencil batch 2, approved by Jafar 2026-10-17)

Frames in `classic.pen`: Email identity `QEixl`, Phone & SMS `C70C3`, Website chat `fAAvd`.
Each frame shows the healthy/approved sample state. Live data and behavior stay real; only the look changes.
Frame IDs documented in `.worktrees/settings-design/Memory/campaigns/contractor-design-concept/parts/a2-settings-design.md`.

## Shared pattern (all three pages)

### Page header (replaces current PageHeader usage)
- Above the title: `Breadcrumbs` from `$lib/components/layout/Breadcrumbs.svelte` with
  items `[{ label: 'Settings', href: resolve('/settings') }, { label: '<Page title>' }]`.
- Header row: page-local flex block — colored icon tile on the left (44px, `border-radius: var(--radius-control)`,
  background `var(--color-informative--surface)`, icon in `var(--color-informative--onSurface)`),
  then title `<h1>` + description `<p>`.
- Do NOT use `PageHeader` for these pages; build the header page-locally (`<header class="<block>__header">`).
  Do NOT modify the shared PageHeader component.
- No eyebrow ("Communications" label is replaced by the breadcrumb). Keep `<svelte:head>` title unchanged.
- **No "Back to settings" button** — approved by Jafar 2026-10-17 (lead's pick).
- **No "Last changed …" chip** — no real live data; decorative data is forbidden.

### Cards
- Keep `SectionBlock` (title / hint / icon / level={2} / actions snippet) as the card: it already matches
  the frame's card header (title + small sub, actions right).

### Tables (Email sender identities, Website chat widgets)
- Use `DataTable` from `$lib/components/data-display/DataTable.svelte` with `variant="card"` and a `row` snippet
  that renders the cells (the snippet renders `<th>`/`<td>` cells; DataTable owns the `<tr>` and the uppercase quiet head).
- Row content per frame: leading cell gets an `Avatar` (`$lib/components/ui/Avatar.svelte`, `id` = row id,
  `size="base"`) with the name bolded and a small secondary line under it; status column uses
  `StatusBadge size="compact"`; actions column keeps the existing Edit button behavior.
- Keep all existing dialog behaviors on the same buttons. Do not add sorting/onRowActivate behavior —
  these are settings tables, not record lists; keep click behavior exactly as today (Edit button opens the dialog).
  No sorting. No row activation.

### Status/pill vocabulary (unchanged semantics, new visuals come from StatusBadge/Badge)
- success = Ready / Published; warning = transitioning states / Draft; critical = Suspended / active holds;
  inactive = Disabled. The "Default" chip: existing `Badge` with dark styling
  `color: var(--color-surface); background: var(--color-surface-reverse)` (dark chip, white text — approved pattern).

### Meters/progress
- Track: `background: var(--color-border)` (frame `$color-border`), `border-radius: var(--radius-circle)`, height like table row bar (~8px).
- Ordinary-usage fill: `var(--color-interactive)` (brand green). Protected-reserve fill: `var(--color-warning)`.
- Meter head: label (600) left; right side shows used count large (700) with the "of N" part in small secondary text;
  "no limit" fallback wording stays as today.
- Small secondary line under the track (recipients left …) as today.

### Icon usage
- Tabler outline icons via `@tabler/icons/outline/<name>.svg?raw`, rendered with `{@html}` and
  `<!-- eslint-disable-next-line svelte/no-at-html-tags -->` comments exactly like the current pages do.
- Section/group icons keep their existing meaning; group title rows in the SMS registration card get a small
  muted inline icon before the h3 (person/building for Business identity, map-pin for Business address,
  user-check for Authorized representative, message for Messaging).

### Rules for every page
- Svelte 5 only. Script logic is NOT changed: same queries, same state, same handlers, same dialogs, same API calls.
  The only allowed script additions are small derived helpers needed to split a label (e.g. used/limit) or map
  unchanged data to the new layout.
- Styles: SCSS + BEM inside the page's own `<style lang="scss">`; semantic tokens only
  (`var(--color-*)`, `var(--space-*)`, `var(--radius-*)`, `var(--typography--*)`). No raw hex values.
- Keep existing loading (LoadingSkeleton) / error (ErrorState) / empty (EmptyState) branches and notices.
  Notices keep their semantic surfaces (`--color-informative--surface` etc.).
- Keep responsive stacking (media queries) working after grid changes: 3-column field grids collapse on narrow widths.
- Desktop-first: frames are 1440px. Do not invent phone layouts; only keep the existing narrow-width stacking sane.
- REAL DATA ONLY: show only what the queries return; the fictional sample content in the frames (Raad LTD, etc.)
  must NOT be copied into code.

---

## Page: Email identity (`src/routes/(app)/settings/communications/email/+page.svelte`)

Order, by frame:
1. Breadcrumbs + header (icon tile: mail icon — already imported as `mailIcon`; title "Email identity";
   description stays "Choose the verified email addresses your team and automations can use.").
2. **"Email included this period"** card (icon `gaugeIcon`, hint unchanged):
   - Two meters side by side (keep the existing `usage` conditionals and wording):
     - Business email: head label + used/limit pair; track+fill green; small line "N recipients left before ordinary email pauses."
     - Protected reserve: same shape; fill amber (`--color-warning`); small line "N recipients left for quotes, invoices, receipts, security notices and replies."
     - Unlimited fallback wording stays ("N sent · no limit" and "No limit applies …" lines).
   - Reset line at card bottom: small calendar/refresh-style icon + "Resets <date>." (data from `resetLabel()`).
   - Keep the reserve-exhausted warning banner above the meters when `usage.essential_reserve_exhausted`.
   - Keep the "period has not started" notice when `!usage`.
3. `EmailSetupCard` — **leave completely untouched** (it renders only when setup is needed; not drawn in the frame).
4. **"Sender identities"** card (icon `mailIcon`, hint "Domains are provisioned and verified by UCRM.", actions: "Add sender").
   - `DataTable variant="card"`, columns: SENDER / DOMAIN / USE / STATUS / (actions, hideLabel).
   - Sender cell: Avatar (id = sender.id, name = display_name) + bold name, below it the email address small +,
     when `sender.is_organization_default`, the dark "Default" chip inline after the email.
   - Status cell: existing `status()` mapping → `StatusBadge size="compact"` (Ready success, Disabled inactive, other warning).
   - Action cell: existing Edit button (`openEdit`) — keep `onhover` prefetch behavior.
   - Keep every alternative state: skeleton, error, no-domains EmptyState, "still being checked" notice, no-senders EmptyState
     (with its Add sender button).

---

## Page: Phone & SMS (`src/routes/(app)/settings/communications/sms/+page.svelte`)

Order, by frame (the frame draws the APPROVED registration state; every other existing state keeps rendering):
1. Breadcrumbs + header (icon tile: `phoneIcon`; title "Phone & SMS"; description stays).
2. **"Readiness"** card (icon `deviceMobileMessageIcon`): four facts in one row with thin dividers between
   (grid `repeat(4, 1fr)`, fact = small secondary label above bold value; collapses responsively):
   - SMS mode → "On" / "Off" (keep existing derivation; "On" may take a small green dot like the frame's "Available").
   - Registration → `StatusBadge` with existing `smsRegistrationBadge(...)` + label logic.
   - Ready numbers → bold count.
   - Outbound availability → green-dot bold "Available" / plain "Not yet available".
3. **"Registration"** card (icon `deviceMobileMessageIcon`; hint line "The name and contact details on everything you send."
   is the frame's generic sub — keep the page as one card with NO extra hint change unless trivial: reuse existing card without hint).
   - Keep: action-needed critical notice, locked-state informative notice, `required_fixes` display, `formError`.
   - Groups (each: small muted icon + h3, then a 3-column field grid that fills row-major; the Messaging group is two columns):
     - Business identity: Legal business name, Business type (Select), [sole-prop toggle + registration-id inputs conditionally], Website.
     - Business address: Street address, Suite/unit, City (row); State/province, Postal code, Country (CountryPicker) (row). Keep the sole-prop hint line.
     - Authorized representative: First/Last/Business title (row); Job position, Email, Phone (row).
     - Messaging (two columns): LEFT: "How will you use texting?" Textarea, consent-method Select, consent-description Textarea.
       RIGHT: "Sample messages (2–5)" (existing add/remove logic, inputs stacked), then Privacy policy + Terms link inputs
       side by side, then Estimated monthly messages Select.
   - Keep the confirm-authorized Checkbox and the Save draft / Submit for review buttons (existing handlers) when editable;
     actions row right-aligned.
4. **Lower two-column row** (grid two columns ~1fr 1fr, stacking on narrow):
   - LEFT column, stacked: **"Phone numbers"** card (icon `phoneIcon`):
     - Number rows: circular icon tile (informative surface + `phoneIcon`), identity = bold name (or number) + secondary number,
       badges row: dark "Default" chip when `is_default_sender`, `StatusBadge` for lifecycle (Ready/Setting up/Restricted/Suspended),
       small chips for SMS/MMS/Voice capabilities, actions Rename (and "Make default" when applicable) — all existing handlers.
     - Empty state (no numbers) and the "contact Jafar" notice stay.
     - **"Holds & opt-outs"** card (icon `banIcon`): two fact tiles (Customers opted out / Active holds) then the
       existing holds list rows or the "No active holds" notice + the "released by Jafar" notice.
   - RIGHT column: **"Compliance & sender info"** card (icon `shieldCheckIcon`):
     - Toggle "Add opt-out instructions…" + its conditional custom-wording Textarea (disabled when off) — as one group.
     - Toggle "Identify the business…" + its conditional wording Textarea — as another group.
     - Re-add wording input (number), then Save compliance settings button right-aligned. All handlers unchanged.

---

## Page: Website Chat (`src/routes/(app)/settings/communications/website-chat/+page.svelte`)

Title casing per frame: "Website Chat". Order:
1. Breadcrumbs + header (icon tile: `messageCircleIcon`; description stays "The chat widgets your website can show customers.").
2. **"Usage and availability"** card: left block — small label "Accepted conversations", big used count with
   "of N" small next to it (unlimited fallback "· unlimited" as today), "Resets <date>" small line;
   right block — meter track+green fill using `conversationUsagePercent` (only when numeric, as today).
   Keep ALL the existing conditional notices below (suspension critical, not-included, no-period, at-cap warnings).
   Keep the "not entitled" EmptyState as the whole page (as today).
3. **"Widgets"** card (hint logic unchanged "2 of 3 widgets used"/unlimited; actions: "New widget", disabled at cap):
   - `DataTable variant="card"`, columns: WIDGET / LAUNCHER / DOMAINS / STATUS / (actions, hideLabel).
   - Widget cell: small neutral icon tile (message-circle icon) + bold widget name.
   - Launcher cell: small message-circle icon in a tiny neutral tile + "Bottom right"/"Bottom left".
   - DOMAINS: origin count. STATUS: `StatusBadge size="compact"` from existing `status()` (Published success, Draft warning,
     Disabled inactive, Suspended critical). Action cell: Edit button (existing `openEdit`).
   - Keep at-cap notice, empty states (with its New widget button).
4. Dialog and everything inside it — **leave untouched** (not drawn in the frame).

---

## Deferred (record, don't run): TypeScript checks, svelte-check, lint, unit tests, production builds — deferred at Jafar's request.

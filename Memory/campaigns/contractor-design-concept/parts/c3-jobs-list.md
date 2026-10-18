# C3 — Jobs list in the concept

**State:** Approved by Jafar 2026-10-18 and built the same day. `concept.pen` frame "Concept · Jobs list · Owner · 1440"
(`t8ULdJ`, right of Home).

**Content source:** the live page `src/routes/(app)/jobs/+page.svelte` and Jobber's Jobs list
(help article "Jobs List Page and Key Metrics": overview by status, Status and Type filters, sortable columns,
New Job and More Actions). No new data or behaviour; demo figures match the Home design.

**What it shows, top to bottom:** header (40 job tile, Jobs, description, More menu, New job) · Needs attention
card: five tiles Late / Unscheduled / Action required / Requires invoicing / Ending soon, each a 32 status-coloured
icon tile, count, label and hint (Late has the act-now red fill, as the live alert tile does), then a strip with
visits today and visits completed in the past 30 days · green feature card "Collected this month" with "Left to
collect on open invoices" · All jobs card: search, Status, Type and Created filters, the table in today's look
(tables are not redesigned), Load more.

**Changes from the live look, for Jafar to confirm:** dark money card becomes the green feature card; status tiles
get coloured icon tiles; client avatars use the client colour instead of one colour per client; "More actions"
becomes the More menu button (still nothing behind it); the "Work & money" eyebrow is dropped.

**Jafar's decision (2026-10-18):** the live list already matched; build only the two improvements, and the
shared parts may change every page that uses them.

**Built:** `AttentionCard` tiles take an optional `icon` (32 status-coloured tile, bordered white tile, 32 count)
on Jobs, Requests, Quotes, Invoices and Clients; `MoneyFeatureCard` is the green feature card on those lists and
the client and invoice pages; new token `--color-feature--alert`. Card corners stay 8 to match the live cards
beside them (Pencil draws 16); the money card keeps its live layout, without the Pencil icon tile.

**Checked:** Playwright, owner, port 5180: the five lists at 1440 light, Jobs and Invoices dark, Jobs at 390,
client and invoice record pages, picked and hovered tiles (picking Unscheduled filtered to 4 jobs).

**Matched to Pencil (2026-10-18, Jafar: "without the table, match the design Pencil has"):** money card gets an
icon tile, figure at the top, panel at the foot, 16 corners (all seven pages); `PageHeader` takes `icon`/`tone`
for the tiled concept header (Jobs only so far); overview and list cards 16 corners; Jobs facts on time/success
tiles; More menu button (still disabled, nothing behind it). Rechecked lists, record pages, dark, 390.

**For the campaign-end checks:** ESLint already flags three older lines in touched files (AttentionCard 150
useless mustache, clients 378 `{@html}`, requests 532 href without resolve).

**Next:** Jafar saves `concept.pen` (Ctrl+S), commit it; then C4 Job details.

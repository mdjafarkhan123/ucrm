# C3 — Jobs list in the concept

**State:** Drawn 2026-10-18, waiting for Jafar's review. `concept.pen` frame "Concept · Jobs list · Owner · 1440"
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

**Next:** Jafar reviews. On yes: record the date here, ask him to save (Ctrl+S), commit `concept.pen`, then C4 Job
details.

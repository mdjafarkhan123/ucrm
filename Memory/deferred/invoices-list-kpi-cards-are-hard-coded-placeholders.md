# Invoices list KPI cards are hard-coded placeholders

**Why postponed:** found 2026-09-24 during the Files and Media 7B-4 live check; outside that campaign's scope.

**What is wrong:** on `/invoices`, the Outstanding, Overdue and Collected this month cards always show "—".
`src/routes/(app)/invoices/+page.svelte` passes `value="—"` literally; no query feeds them, even when the
Overview card counts past-due invoices.

**Reactivates:** the launch-completeness pass (crm-launch-readiness), or any Invoices list work. Must ship
before the first paying client.

**Known constraints:** money totals must respect the viewer's invoice visibility and per-organization currency;
settle them together with the related placeholder gaps (Requests list third KPI card, client financial summary
widget) so the three use one money read model instead of three.

# Shared batch 14 — Products and services — 2026-10-20

Approved Pencil board `vsT0H` (B, rows 1–3). The shared `ProductsAndServicesBlock` now carries the concept look on job, quote, invoice and request records, their new-record forms, and the visit pop-up.

Checked in the running app at 1440px in light and dark mode:

- Job saved, empty and prices-hidden crew views (`job*` screenshots). The empty and crew states use read-only API fixtures; they did not change saved data.
- Quote saved, grouped heading/text/add-on fixture, line menu and discard confirmation (`quote*`). The fixture supplies the extra line kinds and a locked quote; edits were discarded.
- Invoice progress and editable service-date views (`invoice*`); the calendar field and clear control fit inside the line.
- Request saved, loading and couldn't-load states (`request*`); loading and error were forced in the browser.
- New quote, request, invoice and job pricing cards (`new-*`). Empty forms show the two approved choice tiles. The new quote was also checked at 390px, and **Add a line item** opened an editable line (`new-quotes-mobile-light.png`, `new-quotes-line-mobile-light.png`).
- A real recurring, per-visit job's editable visit pop-up (`visit-light.png`, `visit-dark.png`). Its narrow layout shows the full unit prices after the final layout fix.

The script runs completed with no browser page errors. The owner login hit a temporary “Too many attempts” limit during repeated captures, so the final visit and request captures used the listed admin test account. No Save was pressed and no data was written. Type checks, lint and test suites were omitted at Jafar's request.

Capture commands: `node scripts/evidence/pricing-check.mjs docs/evidence/2026-10-20-batch14 <light|dark> <job|quote|invoice|request|forms> [Admin]` and `node scripts/evidence/pricing-visit-check.mjs docs/evidence/2026-10-20-batch14 <light|dark> Admin`, against `npx vite dev --port 5191 --host 127.0.0.1` in the batch worktree.

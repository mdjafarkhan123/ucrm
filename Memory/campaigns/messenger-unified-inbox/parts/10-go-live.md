# Part 10 — Go-live (Meta App Review)

**State:** In progress 2026-10-23. Jafar owns the Meta steps; Claude prepares text and guides.

**Done:** Legal page text written in plain English (Jafar: "should not look like AI slop"; no new design, keep the
live look). Source of truth `docs/marketing-site/legal-pages.md`; handed to the website project as
`UpliftContractor/docs/legal-pages-update.md` (not committed there; the website repo is
`mdjafarkhan123/upliftwebsite`, and Jafar edits it).

**Waiting on Jafar:** put the text into `src/pages/privacy.astro`, `terms.astro`, new `data-deletion.astro`, and the
footer link in `src/data/data.js`, then publish. Confirm the promises: 30-day deletion answer, Amazon SES and
Twilio listed as providers.

**Next:** once the three addresses load publicly, enter them in the Meta App Dashboard (Basic settings), then App
Review: app icon, reviewer instructions with a test login, screencasts for `pages_messaging`,
`pages_manage_metadata`, `pages_show_list`, `business_management`, Business Asset User Profile Access, and the
Human Agent feature. Research notes: `docs/research/messenger-transport-webhooks.md` §6.

**Deletion:** no in-app delete exists yet, so the Data deletion text says "email us" (fixed 2026-10-23). Whole-CRM
deletion is its own campaign, `data-privacy-deletion`; update the page text when it ships.

**Leftovers:** `UpliftContractor/design.pen` holds an unused header and footer drawing, and
`UpliftContractor/design/brand-logo.png` is a logo copy; Jafar decides whether to keep them.

# Part 4 — CRM handoff and isolation

**Campaign:** `uplift-website-admin` · **Plan:** `docs/plans/uplift-website-admin.md` § Product boundary
**Code:** `main`
**Done when:** The access contract and failure behavior are approved.

## Steps

- [x] Inspect the existing CRM authentication, organization, and owner-role implementation read-only.
- [x] Research proven server-to-server handoff and tenant-isolation patterns.
- [ ] Set first-entry and website-assignment behavior.
- [ ] Set short-lived entry, session expiry, owner-role change, and logout behavior.
- [ ] Set server and database isolation guarantees and denied-access screens.
- [ ] Record the approved access contract in the plan.

## Next

Wait for Jafar's answers to Q14–Q19 below, then record the approved access behavior in the plan. Preserve the settled rule that the CMS has no separate login and only the CRM organization owner may enter.

## Notes

The CRM project is `/home/jafar-khan/Documents/Projects/Ucrm` and currently uses Supabase Auth. Do not modify that project during this planning part.

Inspection and standards research: `docs/research/uplift-cms-crm-owner-handoff-2026-10-02.md`. The current CRM allows one organization per user and one owner per organization, re-queries active membership, and atomically demotes the old owner during ownership transfer. It has no CMS site-assignment model yet.

Questions waiting for Jafar:

- **Q14 — Website assignment:** Before the first CMS visit, should Uplift explicitly assign a website to the CRM organization? Recommendation: yes; if none is assigned, keep the owner in CRM and show **Your website hasn't been connected yet** with **Contact Uplift**. Never select or create a website from a URL.
- **Q15 — Expired or invalid entry:** Recommendation: show **This secure link has expired** with **Return to CRM and try again**; never show a CMS login or reveal the technical reason.
- **Q16 — Ownership changes:** Recommendation: block the former owner on their next action, stop saving and publishing, show **Your access changed in CRM**, close their CMS session, and let the new owner enter through CRM.
- **Q17 — Logout:** Should normal logout affect the current browser or every device? Recommendation: current browser only, with a separate **Sign out everywhere** action. The CRM currently logs out every device, so this later needs a small CRM change.
- **Q18 — Wrong or guessed website address:** Recommendation: always show **Website unavailable** without revealing another company, whether its site exists, or switching organizations.
- **Q19 — CMS session expires:** Recommendation: show **Return to CRM**; if the person is still signed into CRM and remains the owner, re-entry is seamless and never asks for a CMS password.

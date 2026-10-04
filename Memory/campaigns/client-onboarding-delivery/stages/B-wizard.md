# Client onboarding and delivery — stage B: Setup wizard

B1 records the answer-storage approach (draft, submitted snapshot, accepted value) in an ADR. Each later part
adds one plan subsection to the same task list. Since plan §2.1 (2026-10-03) B4–B12 build only that stage's
built-in questions and special controls (uploads, domain branches, phone choices); the rest are starter
questions Jafar can edit.

The complete starter content was approved in B3a. B4–B12 implement that list rather than inventing questions
during implementation.

The blueprint needs answer types the editor lacks and forbids flattening them into text boxes, so Jafar
approved (2026-10-03, "the safe way") building A5b–A5f first. B3b and B4–B12 then load each stage into a
draft Jafar publishes.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| B1–B3a Welcome, Your business, package sections, starter content | §§2–3.1 and the approved blueprint | — | — | Done 2026-10-01 to 10-03 — storage is ADR 0005, questions-in-database ADR 0006; blueprint `docs/client-onboarding-setup-content-blueprint.md` approved |
| B3b Rebuild Your business | Blueprint stage 1 replaces today's 25 questions; existing answers kept | A5b, A5e | Legal name shows only when different; old test answers still show | Done 2026-10-04 — migration `20261012090000` (adds the loader B4–B12 reuse); old answers kept. For Jafar to confirm: no \"seasonal\" choice under how customers reach you; address stays separate boxes; \"who else gets setup updates\" is collected only, nothing emails them yet |
| B4 Services + area | §3.2 | B3a, A5b–A5f | Services, areas, and exclusions save and resume | Done 2026-10-04 — blueprint stage 2 loaded into draft 2 by migration `20261013090000`; a full answer saves, resumes and fits the size limit (`starter-content.spec.ts`). For Jafar to confirm: one services list replaces the separate "main service" box (the top promoted service is the main one); urgent services are not put in order; "how far" drops "a mix", since real places are always asked and a distance or travel time is added. Live look comes with A5's hands-on publish |
| B5 Brand + photos | §3.3 uploads with ownership confirmation | B3a | Logo and photos upload; "no logo" never blocks | Done 2026-10-04 — blueprint stage 3 loaded into draft 2 by migration `20261014090000`; no-logo/no-photo client passes, logo and 20 photos save and resume (`starter-content.spec.ts`). Answers too big to store are now refused in plain words. For Jafar to confirm: photos start with "Do you have real photos?" instead of a "none yet" tick; permission and private details are asked per photo, and logo ownership by its own yes/no; brand-guide and brochure files share one upload question; SVG logos are not accepted (not on the safe file list). Live look comes with A5's hands-on publish |
| B6 Website + domain | §3.4, four domain branches, no password asked | B3a | Each branch asks only its own questions | Done 2026-10-04 — blueprint stage 6 loaded into draft 2 (website service only) by migration `20261015090000`; branches, no-password and full save/resume checked in `starter-content.spec.ts`. For Jafar to confirm: "website live now?" is asked to everyone, not only domain owners; featured services and places are a yes/no on the ones already promoted, with a fresh pick only on No; guarantees, licences, insurance and financing are one required yes/no permission plus "what to leave out"; legal wording is a text box plus an optional upload; "not sure" makes no automatic help task. Live look comes with A5's hands-on publish |
| B7 Google Profile | §3.5 | B3a | Contractor stays owner; no Google password field exists | Not started |
| B8 Call routing | §3.6 numbers, ringing, voicemail, missed-call text | B3a | Country-limited number choices; routing answers save | Not started |
| B9 Texting facts | §3.6 registration facts (including the §3.1 registration/tax number B1 left out) and protected provider-document uploads | B5, B8 | Document visible only to the owner and Jafar | Not started |
| B10 Reviews | §3.7 | B3a | No sentiment-based hiding of the Google option | Not started |
| B11 CRM defaults | §3.8 scenario questions; link to existing imports; "who receives new enquiries" should reuse or be reused by B6's `website.form_recipients`, not asked twice | B3a | Skipping imports never blocks | Not started |
| B12 Marketing | §3.9 drafts only | B3a | Nothing can send from setup | Not started |
| B13 Check and send | §3.10 summary, confirmations with wording version, frozen snapshot; the snapshot leaves out answers to questions now hidden by a show-if rule (they stay stored) | B4–B12 | Send to Uplift freezes answers; a later edit shows as a tracked change | Not started |

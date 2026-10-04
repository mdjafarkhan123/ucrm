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
| B1 Welcome + basics | §2 welcome, task list, dashboard setup card replacing `GettingStartedCard`, business basics with autosave and have/don't have/need help | — | Owner fills half on a laptop, signs in on a phone, continues; CRM menu works throughout | Done 2026-10-01 — storage is ADR 0005; questions live in `src/lib/setup/catalogue.ts` |
| B2 Your business | Rest of §3.1: address, hours and exceptions, country, language, time zone and currency confirmation | B1 | Hours with a holiday exception save and reload correctly | Done 2026-10-01 — hours and holiday dates are stored as JSON (`src/lib/setup/hours.ts`); §3.1 opening date and licences left for B7, which is the part that needs them |
| B3 Package sections | Package services decide which stages show (now mostly delivered by A4); shared facts asked once; check and close | A4, B1 | Edition without Website shows no website section; business phone asked once | Done 2026-10-03 — nothing new to build: every setup read filters by package (A4) and a question can sit in only one place per version (A3). Proved in an undone database test (Website package → Raad sees website, Jaaroweb nothing) plus unit tests; Jafar's own check rides with A5's |
| B3a Complete starter content | Every prebuilt stage/question, type, required/defer rule, condition, service dependency, and special control | B3 | Jafar approves one complete contractor setup blueprint backed by research | Done 2026-10-03 — `docs/client-onboarding-setup-content-blueprint.md` approved |
| B3b Rebuild Your business | Blueprint stage 1 replaces today's 25 questions; existing answers kept | A5b, A5e | Legal name shows only when different; old test answers still show | Done 2026-10-04 — loaded into draft version 2 by migration `20261012090000` through `private.setup_load_starter_stage`, which B4–B12 reuse; `starter-content.spec.ts` checks every loaded stage. Old answers kept; their new yes/no gates are suggested (`src/lib/setup/follow-ups.ts`). Two small departures from the blueprint for Jafar to confirm: no "seasonal" choice under how customers reach you (the separate season question covers it), and the address is still separate boxes (answered built-ins keep their type). "Who else gets setup updates" is collected only; nothing emails them yet. Live look comes with A5's hands-on publish |
| B4 Services + area | §3.2 | B3a, A5b–A5f | Services, areas, and exclusions save and resume | Done 2026-10-04 — blueprint stage 2 loaded into draft 2 by migration `20261013090000`; a full answer saves, resumes and fits the size limit (`starter-content.spec.ts`). For Jafar to confirm: one services list replaces the separate "main service" box (the top promoted service is the main one); urgent services are not put in order; "how far" drops "a mix", since real places are always asked and a distance or travel time is added. Live look comes with A5's hands-on publish |
| B5 Brand + photos | §3.3 uploads with ownership confirmation | B3a | Logo and photos upload; "no logo" never blocks | Done 2026-10-04 — blueprint stage 3 loaded into draft 2 by migration `20261014090000`; no-logo/no-photo client passes, logo and 20 photos save and resume (`starter-content.spec.ts`). Answers too big to store are now refused in plain words. For Jafar to confirm: photos start with "Do you have real photos?" instead of a "none yet" tick; permission and private details are asked per photo, and logo ownership by its own yes/no; brand-guide and brochure files share one upload question; SVG logos are not accepted (not on the safe file list). Live look comes with A5's hands-on publish |
| B6 Website + domain | §3.4, four domain branches, no password asked | B3a | Each branch asks only its own questions | Not started |
| B7 Google Profile | §3.5 | B3a | Contractor stays owner; no Google password field exists | Not started |
| B8 Call routing | §3.6 numbers, ringing, voicemail, missed-call text | B3a | Country-limited number choices; routing answers save | Not started |
| B9 Texting facts | §3.6 registration facts (including the §3.1 registration/tax number B1 left out) and protected provider-document uploads | B5, B8 | Document visible only to the owner and Jafar | Not started |
| B10 Reviews | §3.7 | B3a | No sentiment-based hiding of the Google option | Not started |
| B11 CRM defaults | §3.8 scenario questions; link to existing imports | B3a | Skipping imports never blocks | Not started |
| B12 Marketing | §3.9 drafts only | B3a | Nothing can send from setup | Not started |
| B13 Check and send | §3.10 summary, confirmations with wording version, frozen snapshot; the snapshot leaves out answers to questions now hidden by a show-if rule (they stay stored) | B4–B12 | Send to Uplift freezes answers; a later edit shows as a tracked change | Not started |

# Client onboarding and delivery — stage B: Setup wizard

B1 records the answer-storage approach (draft, submitted snapshot, accepted value) in an ADR. Each later part
adds one plan subsection to the same task list.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| B1 Welcome + basics | §2 welcome, task list, dashboard setup card replacing `GettingStartedCard`, business basics with autosave and have/don't have/need help | — | Owner fills half on a laptop, signs in on a phone, continues; CRM menu works throughout | Done 2026-10-01 — storage is ADR 0005; questions live in `src/lib/setup/catalogue.ts` |
| B2 Your business | Rest of §3.1: address, hours and exceptions, country, language, time zone and currency confirmation | B1 | Hours with a holiday exception save and reload correctly | Done 2026-10-01 — hours and holiday dates are stored as JSON (`src/lib/setup/hours.ts`); §3.1 opening date and licences left for B7, which is the part that needs them |
| B3 Package sections | Package ticks decide which sections show; shared facts asked once | A2, B1 | Edition without Website shows no website section; business phone asked once | Not started |
| B4 Services + area | §3.2 | B3 | Services, areas, and exclusions save and resume | Not started |
| B5 Brand + photos | §3.3 uploads with ownership confirmation | B3 | Logo and photos upload; "no logo" never blocks | Not started |
| B6 Website + domain | §3.4, four domain branches, no password asked | B3 | Each branch asks only its own questions | Not started |
| B7 Google Profile | §3.5 | B3 | Contractor stays owner; no Google password field exists | Not started |
| B8 Call routing | §3.6 numbers, ringing, voicemail, missed-call text | B3 | Country-limited number choices; routing answers save | Not started |
| B9 Texting facts | §3.6 registration facts (including the §3.1 registration/tax number B1 left out) and protected provider-document uploads | B5, B8 | Document visible only to the owner and Jafar | Not started |
| B10 Reviews | §3.7 | B3 | No sentiment-based hiding of the Google option | Not started |
| B11 CRM defaults | §3.8 scenario questions; link to existing imports | B3 | Skipping imports never blocks | Not started |
| B12 Marketing | §3.9 drafts only | B3 | Nothing can send from setup | Not started |
| B13 Check and send | §3.10 summary, confirmations with wording version, frozen snapshot | B4–B12 | Send to Uplift freezes answers; a later edit shows as a tracked change | Not started |

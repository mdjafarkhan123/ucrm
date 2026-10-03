# A2 Service ticks — part note

**State:** Waiting for Jafar's answers (asked 2026-10-03). Nothing built yet.

**Found:** upliftcontractor.com sells 6 services: Website, review funnel, missed-call text-back, marketing
campaigns, Google Profile management, CRM app. The package builder already has feature ticks for reviews
(`growth.reputation`), marketing (`marketing`) and missed-call text-back (planned, can't be ticked yet). Only
Website and Google Profile have no tick. Proposal: add those two, and let the other setup sections follow
the existing feature ticks so no service has two ticks.

**Jafar's facts for B6 (website):** Uplift sells no domains. The client buys and owns the domain. Uplift moves
its DNS into Uplift's Cloudflare and hosts its prebuilt Astro site there (git → Cloudflare build). The wizard
asks whether they already own a domain and, if so, the details needed for the move; if not, it tells them
to buy one.

**Jafar's answers 2026-10-03:** (1) Packages vary: smaller ones, and ones with services not on the website —
"its all what I write into the package". (2) Onboarding never waits for a feature to be finished; phone setup
shows whenever the package sells it. (3) He wants to add, remove and edit setup stages and their questions
himself, and asked how much flexibility he should get.

**Proposal sent, waiting for approval:** Jafar keeps a service list, and each package picks services from it.
Each setup stage shows for everyone or for one service. He has a stage and question editor with draft and
publish. Built-in questions (they feed CRM settings or provider registration) can be reworded and moved, not
deleted or retyped (the HubSpot default-property pattern). An answered question's type is never changed.
Removed questions hide; answers are kept. If approved, this revises ADR 0005 decision 3 and the plan, and
adds editor parts before B3.

**Next:** record Jafar's decision in the plan and ADR, re-split stage A/B, then build.

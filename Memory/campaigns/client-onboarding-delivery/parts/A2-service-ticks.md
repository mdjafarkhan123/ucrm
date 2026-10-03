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

**Questions waiting for Jafar (word for word):**
1. Will every client always get all 6 services, or will you sell packages that leave some out?
2. Missed-call text-back isn't finished, so the builder won't let it be ticked yet. Until then, should the
   phone setup questions show for everyone, or stay hidden?
3. "Questions should be flexible so me Jafar can write / tweak questions right?" Choose: a question editor
   in the Jafar panel, or Claude edits them on request.

**Next:** apply the answers, then build the ticks in `src/lib/jafar/packages.ts`, the draft schema, the
builder page, and a migration that freezes them with the edition.

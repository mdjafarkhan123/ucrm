# /jafar first visit waits for the app download

**Why it waits:** Measured 2026-10-10 (phone, 4× slow CPU, 1.6 Mbps, production build): on a first visit every `/jafar` page shows its real data about 5 s in (Leads 5.2 s, booking hours 4.9 s), because the request starts only after about 640 KB of app code arrives. Repeat visits take about 1.1–1.4 s. The plan's target is 2.5 s. This is an app-wide cost, not one page's.
**Brings it back:** The `performance-review` whole-application audit before release, or Jafar reporting a slow first open.
**Known constraints:** Pages whose static heading sat inside the data-loaded branch also paint late; booking settings were fixed that way in E3.

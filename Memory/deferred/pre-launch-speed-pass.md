# Pre-launch speed pass on the staging servers

**Why it waits:** speed must be measured on the real setup (app and database together near customers), and
features still change what phones download. Measuring from Bangladesh through the tunnel misleads.
**Brings it back:** features frozen for launch and the staging VPS running (crm-launch-readiness).
**Known constraints:**
- Serve over HTTP/2 or HTTP/3. Measured 2026-09-29, 4G: HTTP/2 paints the shell in 0.2 s
  and a first click in ~0.1 s; HTTP/1.1 could not finish loading Dashboard in 30 s (133 code files).
- Service worker (SvelteKit built-in): keep app code on the device so repeat visits are instant on any
  network; needs a "new version — refresh" prompt and a mobile-data budget for crews.
- Measure page data calls and server response times from Europe/US/Australia; fix only what evidence shows.
- Tried and dropped: pacing the page warm-up — no gain over HTTP/2.

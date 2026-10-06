# E7 — Guided test run (Jafar clicks, Claude guides)

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md` §10
**Code:** `main`
**Done when:** One fresh pretend client goes from purchase to Project delivered with Jafar clicking; this also closes A5's proof, B9c's login check and E6's full-flow check. Then the rest of the 14 journeys.

## Why a fresh client

Raad LTD's package has no services ticked, so the Website, Google, Calls/texting, Reviews and Marketing stages never show to it. Keep Raad for the role logins.

## Steps (Jafar clicks; guide one click at a time, in plain words; wait for him after each)

- [ ] 0 Before starting: check `https://app.upliftcontractor.com/get-started` loads. If not, start the tunnel: `cloudflared tunnel run` in the background (config `~/.cloudflared/config.yml`); dev server must be on port 5173
- [ ] 1 `/jafar/packages`: one package with all 5 services ticked ("Edit service list" block), saved and published
- [ ] 2 Buy on `/get-started` as a pretend contractor, email `dev.jafarkhan+client1@gmail.com`
- [ ] 3 Jafar confirms payment in `/jafar/onboarding`; the password email arrives; set the password
- [ ] 4 A5 proof: before the client starts, Jafar adds one question in `/jafar/setup` (new draft → Edit questions) and publishes. Only Jafar publishes; keys are never reused
- [ ] 5 As the client: fill every section, see the new question, upload a fake phone bill on Calls, Send to Uplift
- [ ] 6 B9c check: admin sees "Received" only; owner opens it and sees History; Jafar's Setup tab lists it
- [ ] 7 Jafar reviews, returns one section, then accepts all → Ready
- [ ] 8 Delivery: release preview, client sends a correction, launch checks, launch approval, training booked, Live, Delivered; handover pack, dashboard card, Settings card (E6)

## Next

Start at step 0, then step 1. Jafar chose to click himself with Claude guiding (2026-10-06).
Note anything broken or confusing as a fix item; fix small things as found and commit.

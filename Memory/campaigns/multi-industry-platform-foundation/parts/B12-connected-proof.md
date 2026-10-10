# B12 Connected proof — part note

**State:** In progress, claimed by claude-b12 (2026-10-10).

**Method:** The public form must be used through `https://app.upliftcontractor.com` (Cloudflare check only works there; passes by itself, never click or bypass it). Logins use `http://localhost:5173` with test accounts from `Login.md`. Jafar approved one test application through the tunnel.

**Steps**
- [x] Fresh journey: Application submitted — "B12 Proof Roofing", `dev.jafarkhan+b12proof@gmail.com`, Starter Check monthly, application `73e70294-3ed6-4365-ab38-f7685eea3674` (stage was `new`, experience Contractor, type Roofing). Submit took about 20 seconds: mention in report.
- [x] Jafar review on localhost `/jafar/prospects`: kind of business confirmed (Contractor · Roofing), marked reviewed, test payment recorded ($64.50, reference B12-TEST-NO-REAL-FUNDS)
- [ ] Activate account (provisions organization + emails setup link). Outcome check before retry: select id,name from organizations where name='B12 Proof Roofing', and application stage in platform_onboarding_applications for `73e70294…`; never activate twice
- [ ] Setup + Uplift review, role-limited menu, preview, approval, Mark as live
- [ ] Request → Quote → Job/Visit → Invoice/payment, support, overdue pause and recovery
- [ ] Existing Contractor (Raad LTD): history and issued links, role limits
- [ ] Closed new public surface, and Medspa/clinical URLs/APIs refuse Contractor access

**Outside action check:** the application row above (`platform_onboarding_applications`); do not submit a second one.

**Next:** click Activate account in the application panel (if not already provisioned), then get the setup link for the admin and continue to Setup.

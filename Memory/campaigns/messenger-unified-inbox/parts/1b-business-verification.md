# Part 1b — Business portfolio and Meta Business Verification

**Campaign:** messenger-unified-inbox · **Plan:** `docs/messenger-behavior-contract.md` § Assumptions
**Stage:** Planning
**Code:** `main` (no code; Meta dashboard work)
**Done when:** the business portfolio exists, is linked to app 1419027217062214, and Business Verification is submitted (approved is Part 10's gate).
**Read next:** nothing else needed.

## Why now

Verification is only needed to go live for real customers (Advanced Access), but review takes several days, so it starts
early and runs while we build. Development-mode testing does not need it.

## Steps

- [x] Jafar has his Bangladesh trade license in hand (2026-10-18)
- [x] License read 2026-10-18 from `Extra Storage/Documents/Trade-License.pdf` (Dhamsona Union Parishad, Savar). Business name **UPLIFT CONTRACTOR**; address **Dendabor, Polashbari, Savar Cantonment-1344 Ashulia, Savar, Dhaka**; type Online Business; issued 19-09-2026, valid to 30-06-2027. Phone is printed on the license (Jafar types it). Use these exact spellings; never store the national ID or parents' names.
- [ ] Jafar creates the business portfolio at business.facebook.com with those exact details (check none exists first, no duplicates)
- [ ] Open Security Center → Business verification; Meta's screen shows the documents accepted for Bangladesh — read it before uploading
- [ ] Prove the business website: upliftcontractor.com (domain verification; method shown by Meta — likely a DNS TXT record or a meta tag; check where DNS lives before choosing) and use `info@upliftcontractor.com`
- [ ] Jafar uploads the trade license himself and presses the final submit
- [ ] Link the portfolio to the app "Ucrm Messaging" (App settings → Basic → business portfolio, or Meta's connect flow)
- [ ] Record the submission date and status below; check status in Security Center every few days

## Finding 2026-10-18 (blocked)

Meta refused to create the portfolio: "Unable to Create Account — Your Advertising Access is Restricted". Cause (Business
Support Home → My accounts → Md Jafar Khan): the Facebook account is **restricted from advertising** (restriction dated
September; personal ad account marked restricted since about Sept 2021). Meta's wording: Advertising Standards not
followed (rejected ads, circumventing review, fraud, or untrustworthy accounts). It also showed no portfolio exists on this account, and
that Meta found other accounts using an `@upliftcontractor.com` email domain (owner unknown). Facebook account manages
Page **Random News** (ID 1387298701130366), so Part 1's admin check is satisfied. This blocks only Part 1b and Part 10
(going live); development testing and Parts 3–9 do not need a portfolio. Options for Jafar: ask Meta to review the
restriction, or have an unrestricted adult-owned account create the portfolio (ownership choice is Jafar's).

## Next (paused 2026-10-18 by Jafar)

Jafar will use a **second Facebook account he owns** to create the portfolio (his main account is ad-restricted). Resume:
1. Jafar logs out of Facebook in Chrome and logs in with the other account (he types the password). Ask him first that it is in his
   own name and under his control.
2. Read-only check: `https://www.facebook.com/business-support-home/` → My accounts (no restriction, no portfolio yet).
3. Open `https://business.facebook.com/business/loginpage/?create_business_portfolio_for_bm=1`, fill name **Uplift Contractor**,
   email `info@upliftcontractor.com` (Jafar can open that inbox); Jafar presses submit and types the emailed code.
4. Security Center → Business verification: read Meta's Bangladesh document list before Jafar uploads the license
   (`Extra Storage/Documents/Trade-License.pdf`); Jafar uploads and submits.
5. Add the new account as admin of app 1419027217062214 and link the portfolio. The app was created by the restricted
   account, so Meta may force an ownership move — report it to Jafar if so.

## Update 2026-10-18 (later): portfolio already exists on the SECOND account

Jafar's second Facebook account (profile id 61590265614105, name "Jafar Khan") already owns portfolio **Uplift Contractor**,
ID **855656587107152**, created by JAFAR AHMMED on 2026-06-05 (legal name on his NID/license is Jafar Ahmmed). Unverified; details empty;
`info@upliftcontractor.com` "Pending confirmation"; a trusted domain exists. That account also owns apps "Unified Inbox"
(2051753769098702, linked to the portfolio, made with the legacy "Other" use case) and "jk" (1679372116637045). Do NOT create a second portfolio.
Our app "Ucrm Messaging" (1419027217062214) is owned by the restricted first account (Md Jafar Khan, only admin).
Phone on license: 01902316940 (Jafar gave it). Plan Jafar approved: (1) Jafar confirms the email link; (2) business details filled
(name UPLIFT CONTRACTOR, Bangladesh, Dendabor, Polashbari / Ashulia / Savar / Dhaka / 1344, phone, https://upliftcontractor.com) and
saved after Jafar checks; (3) Jafar uploads the license and submits; (4) add 2nd account as Administrator of Ucrm Messaging (first try failed
before the 2nd account was a registered developer; retry), then connect the app to the portfolio. Adding app roles is a permission grant:
the Chrome permission check blocks Claude from it, so Jafar presses Add himself.

## Submitted 2026-10-18

Business Verification for portfolio 855656587107152 (Jafar's 2nd account) submitted by Jafar on 2026-10-18: use case "App requires access to permissions on Meta for Developers", Sole Proprietorship, name UPLIFT CONTRACTOR, address as on the license (State Dhaka, 1344), phone +8801902316940, https://upliftcontractor.com/, Trade-License.pdf uploaded, email confirmed by code to info@upliftcontractor.com. Security Center shows **In review**, "about 2 business days". Never resubmit while In review. Remaining 1b steps: check status in Security Center around 2026-10-21; add 2nd account as admin of Ucrm Messaging (Jafar presses Add) and connect the app to the portfolio.

## Verified 2026-10-18

Checked live in Chrome (Business settings → Business info, portfolio 855656587107152): Business verification status **Verified**, Oct 18, 2026. The same page shows a separate **Access verification** (Tech Provider) with "Start verification", not started; it likely gates Part 10 (Advanced Access) — confirm then. "WhatsApp needs more information" is out of scope. `info@upliftcontractor.com` still shows "Pending confirmation" on the profile.

## Decision 2026-10-18: new app on the 2nd account

Jafar dropped the first (restricted) account entirely. New app **Ucrm Messaging**, App ID **1709471683925717**, created by Jafar on the 2nd account
(use case "Engage with customers on Messenger from Meta" only; contact email info@upliftcontractor.com; connected to portfolio Uplift Contractor
855656587107152; unpublished, development mode). The old app 1419027217062214 (first account) is abandoned; "Unified Inbox" and "jk" on the 2nd account are untouched.
`.env` META_APP_ID and PUBLIC_META_APP_ID now hold the new ID. **META_APP_SECRET still holds the OLD app's secret: Jafar must re-enter his password in
App settings > Basic and paste the new secret into `.env`.** Test Page "Random News" belongs to the first account; the 2nd account needs a Page of its own or a role on it.

## Outside actions

- Business portfolio exists (created 2026-06-05 on 2nd account, ID 855656587107152) — done
- Business Verification submitted — check: Security Center shows "In review" — done 2026-10-18. Never resubmit while "In review".

## Notes

- Unverified: Meta's own Bangladesh document list. Other platforms accept a trade license; Meta accepts official
  documents showing legal name, address or phone. Not accepted generally: personal IDs, invoices, self-filed tax papers,
  website printouts. If the license is rejected, ask Jafar for a registration or incorporation certificate.
- Unverified: whether contractors who connect their own Page also need verification — answer in Part 2.
- Review usually takes several days.

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

## Outside actions

- Business portfolio created — check: it appears in business.facebook.com business list under the exact legal name — pending
- Business Verification submitted — check: Security Center shows "In review" with the submission date — pending. Never resubmit while "In review".

## Notes

- Unverified: Meta's own Bangladesh document list. Other platforms accept a trade license; Meta accepts official
  documents showing legal name, address or phone. Not accepted generally: personal IDs, invoices, self-filed tax papers,
  website printouts. If the license is rejected, ask Jafar for a registration or incorporation certificate.
- Unverified: whether contractors who connect their own Page also need verification — answer in Part 2.
- Review usually takes several days.

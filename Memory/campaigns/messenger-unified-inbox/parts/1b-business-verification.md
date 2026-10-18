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
- [ ] Ask Jafar for the exact business name, address and phone as printed on the license (a mismatch is the usual rejection)
- [ ] Jafar creates the business portfolio at business.facebook.com with those exact details (check none exists first, no duplicates)
- [ ] Open Security Center → Business verification; Meta's screen shows the documents accepted for Bangladesh — read it before uploading
- [ ] Prove the business website: upliftcontractor.com (domain verification; method shown by Meta — likely a DNS TXT record or a meta tag; check where DNS lives before choosing) and use `info@upliftcontractor.com`
- [ ] Jafar uploads the trade license himself and presses the final submit
- [ ] Link the portfolio to the app "Ucrm Messaging" (App settings → Basic → business portfolio, or Meta's connect flow)
- [ ] Record the submission date and status below; check status in Security Center every few days

## Next

Ask Jafar for the license details. Then open `https://business.facebook.com/` in a new Chrome tab (Claude in Chrome tab
group) and guide him screen by screen. Passwords, document upload and the final submit are Jafar's.

## Outside actions

- Business portfolio created — check: it appears in business.facebook.com business list under the exact legal name — pending
- Business Verification submitted — check: Security Center shows "In review" with the submission date — pending. Never resubmit while "In review".

## Notes

- Unverified: Meta's own Bangladesh document list. Other platforms accept a trade license; Meta accepts official
  documents showing legal name, address or phone. Not accepted generally: personal IDs, invoices, self-filed tax papers,
  website printouts. If the license is rejected, ask Jafar for a registration or incorporation certificate.
- Unverified: whether contractors who connect their own Page also need verification — answer in Part 2.
- Review usually takes several days.

# Lead sources are typed many ways

**Why it waits:** Found 2026-10-01 during Pipeline D2, outside that part. Clients carry lead source as free
text: test data has "Referral" beside "referral", plus "Google" and "staff" from the dashboard quick add and
imports, none on the client form's list (`src/lib/clients/lead-sources.ts`).
**Brings it back:** Stage F's source report, or Jafar asks for tidy lead sources.
**Known constraints:** The Pipeline filter already ignores capitals and lists real spellings
(`20261003090000`). Marketing customer groups still match exactly (`lead_sources` rule in the baseline), so
"referral" clients miss a "Referral" group. Jobber keeps a fixed, owner-edited source list; research it first.

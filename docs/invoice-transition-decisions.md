# Invoice transition decisions — approved

Jafar approved all five directions and supplied their concrete behavior. The authoritative rules now live
in `docs/invoice-behavior-contract.md`, section **Approved transition decisions D1–D5**.

- D1: partial Draft remains Draft; credit/prepayment until issue; full payment still makes Paid.
- D2: explicit ordinary payment disposition before Void; automatic deposit release only after eligibility.
- D3: Invoice-owned retained progress correction/replacement; replacement active; payments do not move implicitly.
- D4: explicit linked rebill; no automatic source requeue or independent duplicate billing.
- D5: previewed, permission-checked Visit completion atomic with Draft creation; no automatic Job closure.

D1–D4 are approved UCRM choices, not newly verified Jobber behavior. D5 includes the approved safety improvement.
Part 2 design is now authorized for review; no migration or application implementation is authorized.
See `docs/invoice-part-2-design.md` for the review proposal.

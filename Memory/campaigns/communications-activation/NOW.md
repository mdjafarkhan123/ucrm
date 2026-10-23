# Communications Activation: Current Checkpoint

## Goal

Deliver email and SMS through the unified inbox, with safe channels for dependent products. Email is live;
SMS Stages 1–9 and MMS are built. Live SMS stays off until its launch gate passes.

## Active part

**Stage 10 global texting.** Core agreement: `docs/global-sms-behavior-contract.md` (GHL journey; Uplift handles
provider setup). Comparison: `docs/global-sms-codex-review-plan.md`; evidence:
`docs/research/global-sms-country-requirements-2026-10-22.md`. Approved designs: `concept.pen` and
`parts/stage10-design.md`. Parts 1–3 built (`parts/stage10-part1.md`, `parts/stage10-parts23.md`);
Parts 4a–4c built (`parts/stage10-part4.md`). Parts 5a and 5b (To do queue + business countries card) built (`parts/stage10-part5.md`).

## Next

5b and the first 5b-2 pieces (business Texting view, Waiting on Twilio) are built on `claude/stage10-part5b`, **waiting
to merge** once main is free. Next: plan Countries & prices with Part 6. Jafar must decide the undrawn Businesses
tab, Add a country and Show its history. 5c needs a Pencil drawing.

## Constraints

No placeholder registrations, purchases, fake-ready senders or live SMS. Real proof waits for truthful first-business
details and Jafar’s authorization. The SMS wake cron remains inactive. Platform ISV approval is recorded but not
configured; it does not replace client registration. No regional app block.

Resume: `read memory and continue communications-activation` — merge 5b, then Countries & prices.

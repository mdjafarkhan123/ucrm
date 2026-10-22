# Communications Activation: Current Checkpoint

## Goal

Deliver email and SMS through the unified inbox, with safe channels for dependent products. Email is live;
SMS Stages 1–9 and MMS are built. Live SMS stays off until its launch gate passes.

## Active part

**Stage 10 global texting.** Core agreement: `docs/global-sms-behavior-contract.md` (GHL journey; Uplift handles
provider setup). Comparison: `docs/global-sms-codex-review-plan.md`; evidence:
`docs/research/global-sms-country-requirements-2026-10-22.md`. Designs approved in `concept.pen`
(`parts/stage10-design.md`). **Part 1 built 2026-10-22** — `parts/stage10-part1.md`. **Part 2 (buy a number)
built 2026-10-22 on branch `claude/stage10-parts23`, not merged** — `parts/stage10-parts23.md`.

## Next

Part 3 server is built and pushed; build its screens (step list in `parts/stage10-parts23.md` § Next) in
`.worktrees/stage10-parts23`, then merge Parts 2+3. Before any live purchase: Jafar's number prices and the
monthly renewal decision.

## Constraints

No placeholder registrations, purchases, fake-ready senders or live SMS. Real proof waits for truthful first-business
details and Jafar’s authorization. The SMS wake cron remains inactive. Platform ISV approval is recorded but not
configured; it does not replace client registration. No regional app block.

Resume: `read memory and continue communications-activation` — build the Stage 10 Part 3 screens.

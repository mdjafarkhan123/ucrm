# Communications Activation: Current Checkpoint

## Goal

Deliver email and SMS through the unified inbox, with safe channels for dependent products. Email is live;
SMS Stages 1–9 and MMS are built. Live SMS stays off until its launch gate passes.

## Active part

**Stage 10 global texting.** Core agreement: `docs/global-sms-behavior-contract.md` (GHL journey; Uplift handles
provider setup). Comparison: `docs/global-sms-codex-review-plan.md`; evidence:
`docs/research/global-sms-country-requirements-2026-10-22.md`. Designs approved in `concept.pen`
(`parts/stage10-design.md`). **Part 1 built 2026-10-22** — `parts/stage10-part1.md`. **Parts 2 + 3 built
2026-10-22** (buy a number + paperwork screens) — `parts/stage10-parts23.md`. **Part 2 (buy a number)
built 2026-10-22 on branch `claude/stage10-parts23`, not merged** — `parts/stage10-parts23.md`.

## Next

Stage 10 Part 4: readiness of each number (board `NbWfA`, plan § Part 4). Parts 2 + 3 are merged; their live
proof waits on number prices and Jafar's go-ahead. Open question for Jafar in the part note (decision email).

## Constraints

No placeholder registrations, purchases, fake-ready senders or live SMS. Real proof waits for truthful first-business
details and Jafar’s authorization. The SMS wake cron remains inactive. Platform ISV approval is recorded but not
configured; it does not replace client registration. No regional app block.

Resume: `read memory and continue communications-activation` — build the Stage 10 Part 3 screens.

# Communications: Current Checkpoint

## Goal

Build one secure Conversations experience across independently gated email, Website Chat, Meta, and Twilio channels.

## Current part

Part 7 (Allowances, reputation, Jafar controls) is **closed at code level** — 7.6b shipped
2026-08-28 (migration `20260907090200`, pgTAP 16 green, usage card on `/settings/communications/email`).
Both Part 7 screens sit on ROADMAP.md's pending browser list for the Part 9 pass.

Part 8 (Suspension, closure, and cleanup) is the next dependency-ready part and is **unscoped**.

## Exact next action

Scope Part 8 with Jafar before writing code: read ROADMAP.md's Part 8 row and
docs/contractor-email-contract.md §§ Platform Owner controls and Queueing/retries/history, then
propose the slice list, dependencies, and completion gates. Jafar's 2026-08-27 "no per-slice plan
approval" applied to Part 7 only — the Part 8 scope itself still needs his approval.

## Blockers

None. The HTTP email-worker transport is still a stub — expected; the DB layer runs ahead of it.

## Essential pointers

- parts/7.md — the few non-discoverable Part 7 risks that still change future work (which migration
  holds the live claim body, the effective-dated one-call-per-txn edge, no `authenticated` grants)
- ROADMAP.md — Part 8 row and the pending browser-verification list

## Completion gate

Part 8 is ready when Jafar has approved its slice list and ROADMAP.md and this checkpoint name the
same first slice.

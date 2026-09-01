# Contractor Settings: Current Checkpoint

## Goal

Give contractors one permission-aware control room for business identity and feature-owned settings.

## Where things stand

- **6F-1 closed 2026-08-31** — Jobber Quote-follow-up parity shipped (migration `20260831103248`, 26 pgTAP
  green, evidence in the contract's § 6F-1 section). Client follow-up preference is enforced at intake and
  send, live work stops as soon as a Quote leaves Awaiting response, and waits are anchored to the original
  send in the organization's timezone.
- **6E-1 closed 2026-08-31** — automation retention sweep; nightly `pg_cron` job is live.
- Jafar decided 2026-08-31 that the VPS must not block further Automation work. **6D-6** load evidence and
  **6E-2** retention UI stay deferred until he buys it; no capacity claim or broad rollout before 6D-6 passes.
- Nothing in Part 6 is dependency-ready and unstarted: **6F-2–6H** need a confirmed Jobber behavior plus a
  real owning-domain command, and need Jafar's approval before planning.
- Earlier Part-6-adjacent gaps still open: **3E** (Team and access), **3F** (Scheduling-gated), **4**
  (Request/booking forms — needs Requests + Scheduling), **5** (feature-owned settings, per domain).

## Exact next action

Ask Jafar which thread to open: **3E Team and access** (the only one with no external dependency), or a
6F-2–6H pack once he names the behavior. Do not start either without his pick.

## Essential pointers

- docs/automation-behavior-contract.md § 6F-1 Quote follow-up parity / Scheduling / Deferred scope
- Memory/campaigns/contractor-settings/ROADMAP.md — full part status, read when a thread is chosen
- Memory/deferred/automation-6d2-action-park-assertions-are-stale.md — 6D-2's suite still asserts pre-6D-3
  behavior; not a product defect

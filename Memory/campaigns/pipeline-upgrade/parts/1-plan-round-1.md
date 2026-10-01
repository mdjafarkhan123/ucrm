# 1 — Plan: round 1 choices

**Campaign:** pipeline-upgrade · **Plan:** `docs/sales-pipeline-behavior-contract.md` § Still unclear
**Code:** `main` (planning only — no code)
**Done when:** Every Q1–Q11 answer is written into the plan body

## Steps

- [x] Audit the built Pipeline against Jobber, Pipedrive, HubSpot, and Housecall Pro
- [x] Ask Jafar round 1 (Q1–Q11) with recommendations, 2026-10-01
- [x] Independently verify Claude's claims against current official sources, 2026-10-01
- [ ] Write each answer into the plan body and remove it from Still unclear
- [ ] Add the questions the answers open to Still unclear for part 2

## Next

Wait for Jafar's answers to the corrected round 1 below. Then edit the plan: settled behavior into the body,
remove the superseded Q1–Q11 wording from Still unclear, and update Boundaries where scope changes.

## Notes

Claude's central Jobber findings were mostly right, but the independent check corrected overclaims: forward-only
is Jobber-specific; several quick actions and lead-source behavior are wider-market improvements, not documented
Jobber parity; independent lane loading is unverified; and forecasting exists in contractor CRM. Corrected round 1:

1. Use Tasks as the only next-follow-up truth; migrate existing dates into Tasks, prioritize overdue/today/no-task
   cards, keep Expected close as an optional sort, and use owner-set per-stage inactivity warnings separately.
2. Count request-to-job and standalone jobs as Won, label direct jobs separately, and exclude direct jobs from
   request/quote conversion denominators.
3. Ship one protected contractor pipeline with custom follow-up stages before launch; defer multiple pipelines,
   custom-stage automations, and approval gates until their need is proven.
4. Ship responsive web before launch with tap/Move controls; keep a separate native app for later.
5. Add saved filters, table view, and safe bulk ownership/stage follow-up tools before launch.
6. Keep weighted probability forecasting and AI summaries optional/post-launch; retain pipeline value and Expected
   close without pretending a probability is known.

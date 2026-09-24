# Email warm-up for new contractor sending domains — research (2026-09-23)

## Problem

UCRM's warm-up ceiling (`private.resolve_communication_email_warmup_ceiling`) is calendar-only: days 1–3 = 100/day,
4–7 = 250/day, 8–14 = 500/day, then no cap. It advances whether or not the domain sent anything or how that mail
performed. A domain that sends nothing for 14 days is uncapped on day 15 with no real reputation earned.

## What the industry does

- **HighLevel (GHL), LC Email sub-account ramp-up** — closest analog (multi-tenant, shared infrastructure). Fixed
  stages with daily limits (1,000 → 2,500 → 5,000 → … → 15,000, new stage 25,000). Graduation is **behavior-based,
  not time-based**: a stage rolls forward only while sending stays healthy; high bounce rate, delivery below 95%,
  or complaint thresholds hold or **downgrade** the stage. GHL replaced manual per-account overrides with this
  automatic path because one account's bad sending harms everyone sharing the reputation.
  [HighLevel help](https://help.gohighlevel.com/support/solutions/articles/155000007790-lc-email-sub-account-rampup-smart-sending-graduation-shared-domain-reputation-protection)
- **Jobber Campaigns** — no published warm-up stages. Campaigns over 500 recipients send gradually; Jobber
  monitors during sending and **stops a campaign** that shows problems (e.g. spam marks). Limit 15,000 recipients.
  [Jobber help](https://help.getjobber.com/en/articles/campaigns-marketing-tools/)
- **Amazon SES (AWS guidance)** — ramp gradually and adjust from real feedback; hard bounces below ~2% (AWS acts
  near 5%), complaints below 0.1% (AWS warns at 0.08%, restricts near 0.5%); send to most-engaged recipients first.
  [AWS warming guide](https://aws.amazon.com/blogs/messaging-and-targeting/guide-to-ip-and-domain-warming-and-migrating-to-amazon-ses/),
  [SES dedicated IP warming](https://docs.aws.amazon.com/ses/latest/dg/dedicated-ip-warming.html)
- **Klaviyo** — start low, send consistently, send first to recently engaged contacts.
  [Klaviyo help](https://help.klaviyo.com/hc/en-us/articles/20413890435355)

## What UCRM already has

- Marketing-only automatic reputation pause (`20260923120000_marketing_reputation_pause.sql`): spam complaints and
  hard bounces over 24h/7d windows pause Marketing — the equivalent of Jobber's stop-on-problem.
- SES VDM engagement tracking and SES event ingestion, so bounce/complaint/delivery data per organization exists.

## Gap and recommended pattern

Missing piece: **earned graduation** (GHL's model). Recommended shape, to be designed and approved before build:
keep the day-based stages as a minimum time per stage, and advance a stage only when the organization has actually
sent a minimum volume in its current stage with bounce and complaint rates under thresholds; hold (or step down)
otherwise. Reuse the existing reputation signals and thresholds rather than adding a new data source. Mail to the
SES mailbox simulator must not count as earned reputation.

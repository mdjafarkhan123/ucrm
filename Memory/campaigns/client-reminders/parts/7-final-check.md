# 7 — Final check

**Campaign:** client-reminders · **Plan:** `docs/client-reminders-behavior-contract.md`
**Done when:** All checks pass on `main`; launch-roadmap items ticked.
**Claim:** write `sonnet-cr-7`; release when finished.

## Steps

- [x] Owner login, desktop: client switches dialog (Clients → client → pencil → Configure) shows all five switches; overdue-invoice says "Not sending" (its recipe is off), visit and job follow-up show no warning. Communication tab lists the sent thank-you, overdue, booked and moved emails.
- [x] Switches on phone width (390px frame): dialog fits, no overflow. Note: client header card at phone width scrolls sideways and clips "Request a review" (not from this campaign; not fixed)
- [ ] Logins: admin, office, sales, finance, field member — who sees or edits the switches
- [x] "Notify customer" box seen ticked-by-default on: calendar drag (Move visit), quick-create (New job), assessment panel editor. Unscheduled drawer was empty so not tried live (shares the drag's page-level box)
- [ ] Tick the launch-roadmap items (`docs/crm-launch-implementation-roadmap.md` ~lines 204–213)

## Next

Role logins from `Login.md` (office, sales, finance, field member, admin): client switches dialog + schedule box. Tip: the ⋮ menu on the client page holds Archive; use the pencil icon to edit.

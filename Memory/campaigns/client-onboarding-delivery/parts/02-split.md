# 2 — Split the build

**Campaign:** client-onboarding-delivery · **Plan:** `docs/client-onboarding-delivery-behavior-contract.md`
**Code:** `main`
**Done when:** Jafar approves the part sizes, order, and dependencies

## Steps

- [x] Check what already exists (buy form, payment confirm, account creation, imports, getting-started card)
- [x] Draft stages and parts; show Jafar
- [ ] Revise until approved, then write stages into `ROADMAP.md` + `stages/*.md`

## Next

Wait for Jafar's answer to the question below. Revise the draft, then write it into the roadmap.

## Notes

Already built and matching plan §1: `/get-started` form, Jafar's confirm-payment and provision actions. Old
4-item `GettingStartedCard` is replaced by the setup card. Imports tools exist and are reused. Package
editions store managed services (website, Google) as free text, so the wizard needs fixed service ticks.

Draft (shown 2026-10-01):
- **A Groundwork:** A1 check purchase/payment journey against plan, fix gaps · A2 fixed service ticks on
  package editions (waits package-builder P16)
- **B Setup wizard:** B1 welcome + task list + "Your business" with autosave/resume (riskiest: answer-storage
  ADR) · B2 package decides sections, shared answers once · B3 services/area + brand/photos · B4 website/domain +
  Google Profile · B5 calls/texting + protected documents · B6 reviews, CRM defaults, marketing, imports link ·
  B7 check and send to Uplift
- **C Uplift review:** C1 Jafar's client list + client view · C2 accept/ask/return a section · C3 Ready for
  Uplift + blockers + 7–10 day range + facts fill CRM settings · C4 reminder emails
- **D Support Messenger** (can run beside B): D1 chat + Jafar Support Inbox, live, unread, who-sees-what ·
  D2 attachments, topics, email fallback, resolve/reopen, Jafar starts chats · D3 "Ask Uplift" from a section
- **E Delivery:** E1 project status timeline + provider-wait badges · E2 preview, one correction round, versioned
  launch approval · E3 launch checks, training, handover pack · E4 full 14-journey test + security check

Question to Jafar, word for word: "Is any piece too big or too small, and is the order right? In particular:
should the Support chat (D) be built before the setup wizard instead of beside it?"

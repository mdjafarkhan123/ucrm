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

Sizing rule (Jafar, 2026-10-01): each part small enough that a session reads one plan subsection and a few
files, so context stays light. Revised draft (shown 2026-10-01), ~34 parts:
- **A:** A1 check buy/pay journey · A2 package service ticks (waits package-builder P16)
- **B wizard:** B1 welcome + task list + business basics with autosave (answer-storage ADR) · B2 rest of
  §3.1 · B3 package decides sections · B4 §3.2 · B5 §3.3 · B6 §3.4 · B7 §3.5 · B8 §3.6 call routing · B9 §3.6
  texting facts + protected uploads · B10 §3.7 · B11 §3.8 · B12 §3.9 · B13 §3.10 check and send
- **C review:** C1 client list · C2 client page with sections · C3 accept/ask/return + help tasks · C4 Ready for
  Uplift + countdown · C5 facts fill CRM settings · C6 reminders
- **D chat** (beside B, Jafar did not object): D1 button + thread + Support Inbox · D2 live + unread · D3
  who-sees-what · D4 attachments + topics · D5 email fallback, resolve/reopen, Jafar starts · D6 Ask Uplift
- **E delivery:** E1 timeline · E2 provider badges · E3 preview + correction · E4 launch approval · E5 launch
  checks · E6 training + handover · E7 14 journeys · E8 security sweep

Question to Jafar, word for word: "Is this smaller split OK to save as the build plan?"

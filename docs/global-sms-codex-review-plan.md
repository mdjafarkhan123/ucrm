# Global SMS launch readiness — Codex comparison plan

**Status:** Comparison reviewed 2026-10-22. Jafar approved the combined agreement in the
[canonical plan](global-sms-behavior-contract.md), incorporating the corrections below. This document remains
the historical comparison; follow the canonical plan and campaign checkpoint for current authorization.

## Goal and reference

Every business may select its country. A subscribed business uses Phone & SMS to find a number, see its text, picture and call capabilities and price, complete applicable paperwork and registration, and understand exactly when it can send. No region is blocked by UCRM. SMS availability follows the actual number, sender, destination and provider rules; a voice-only number or an empty search is not presented as texting-ready. Real end-to-end proof waits for the first paying business.

Follow [HighLevel's number purchase flow](https://help.gohighlevel.com/support/solutions/articles/155000003226) and [regulatory bundle experience](https://help.gohighlevel.com/support/solutions/articles/48001213216), within UCRM's existing Phone & SMS, Conversations, Automation, SMS usage and Jafar controls. HighLevel does not publish a fixed country count, and its present carrier availability must not be assumed identical to our Twilio account. Twilio provides [country and number inventory](https://www.twilio.com/docs/phone-numbers/api/availablephonenumber-resource), [regulatory requirements](https://www.twilio.com/docs/phone-numbers/regulatory/api/regulations), and separate [number](https://www.twilio.com/docs/phone-numbers/pricing) and [message](https://www.twilio.com/docs/messaging/api/pricing) prices.

## Product journey and build order

1. **Design first in Pencil.** Review Add number, Compliance, per-number readiness, charges and Jafar's provider-readiness controls. Reuse existing components and approval flow.
2. **Discover countries and requirements.** Keep business country selection global. Server-side Twilio reads supply available phone-number countries, types, capabilities, current inventory, number prices and regulatory form requirements. Cache briefly; show provider-unavailable and no-SMS-inventory states distinctly. Do not encode an Asia exclusion or assume the Regulations API describes all messaging or consent rules.
3. **Complete paperwork and buy safely.** In the organization's Twilio subaccount, collect the exact address, identity and document fields requested for its country, number type and end-user type. Show review, rejection and resubmission. Before purchase, show the final monthly selling charge and approved bundle or address requirement; use an idempotent purchase record, audit the result, and attach the acquired number to its Messaging Service.
4. **Make each sender ready.** Extend the existing US 10DLC flow, add toll-free verification, and derive readiness from the number and its actual traffic destination. A Canadian local number texting only Canada must not be forced into US 10DLC. Do not assume a bundle alone authorizes SMS everywhere: check destination-specific sender registration, use-case and route requirements before activation. Show the next required step beside each sender.
5. **Send and charge correctly.** Check recipient country, sender suitability, consent, opt-out, quiet hours, SMS/MMS capability, credit and rate at estimate, enqueue and dispatch. Localize Advanced Opt-Out only for configured languages and country overrides; [Twilio does not translate keywords automatically](https://www.twilio.com/docs/messaging/tutorials/advanced-opt-out). Use the existing credit ledger and Jafar-published retail rates; Twilio cost is an input, while the margin and charged rate remain UCRM-owned and visible before sending. Keep an auditable frozen rate on each charge.
6. **Control destinations honestly.** Each organization has its intended texting destinations. Jafar sees whether Twilio has enabled each destination in the relevant subaccount. [Twilio SMS Geo Permissions cannot be changed through its API](https://www.twilio.com/docs/messaging/guides/sms-geo-permissions), so a requested new destination requires an account-admin Console step and a verified outcome. A local switch alone never marks that destination ready.

## Public interfaces and stored state

Add organization-scoped, Zod-validated `/api/*` reads and writes for country/number search, compliance submissions, purchase requests, sender readiness and destination requests. Store provider IDs, submission versions/status, purchase idempotency and audit history server-side; keep uploaded identity documents private and tenant-isolated. Reuse sender identities, registrations, organization SMS mode, retail-rate versions, balance and conversation records. Keep Twilio credentials and its approved ISV profile ID server-side.

## Verification and activation

- Simulate Twilio inventory changes, unavailable pricing, bundle rejection, interrupted or duplicate purchase, registration decisions, provider callbacks, geo-permission mismatch, opt-outs, unsupported MMS, failed delivery and credit reservation/settlement.
- Use read-only Twilio calls across representative countries and number types to validate discovery, regulation and pricing mappings. Screen-check desktop/mobile, light/dark and loading, empty, pending, error and ready states.
- Keep real purchases, registrations and outbound sending off while no truthful business details exist. With the first paying business, verify its documents, number purchase, required registration, actual Twilio destination permission, inbound reply, opt-out, outbound delivery and ledger before its SMS service is activated. Repeat the applicable country checks for later destinations; the global country picker itself is not proof that every route works.

## Points to compare at review

The other plan says live Twilio rules alone make a new country work without code changes, that an approved bundle is enough outside North America, and that Advanced Opt-Out handles other languages. This proposal retains the global picker but makes messaging-rule review, destination permissions and explicitly configured opt-out languages part of readiness. It also separates Twilio's provider price from Jafar's selling rate and existing credit margin.

**Assumptions:** WhatsApp, porting and HighLevel's separate paid identity-check experience remain later work. Jafar's approved platform ISV profile does not replace each client's own identity and sender requirements. No live provider spending is authorized by this comparison plan.

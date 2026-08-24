# Billing address shape on the client

- **Priority:** P3


- **Campaign:** `clients-properties` Part 7, deferred out of scope on 2026-08-17.
- **Reason:** Jafar rejected a billing address on the client page during Part 6 — it has no meaning until
  something is billed. Do not reintroduce it before then.
- **Reactivation trigger:** The Invoicing campaign needs an address to bill to.
- **Prerequisites:** Invoicing decides whether billing address is its own field or a chosen property.
- **Checkpoint:** `docs/client-property-behavior-contract.md`.


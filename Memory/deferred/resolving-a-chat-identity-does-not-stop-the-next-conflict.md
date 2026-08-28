# Resolved Website Chat identities can conflict again

- **Priority:** P2
- **Why postponed:** Resolving one session does not reconcile phone/email values held by two Clients, so the next session repeats the conflict. Merge versus move is an unresolved product decision.
- **Reactivate when:** Jafar chooses a reconciliation model, Client merge is scoped, or contractors report repeats.
- **Constraint:** A session with messages has no dismiss path; identity changes must preserve both Clients' records safely.
- **Pointer:** Current Website Chat identity commands and docs/website-chat-behavior-contract.md.

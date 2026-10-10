# Multi-industry platform foundation — now

**Goal:** Jafar and authorized Uplift teammates can take a supported business from Application through payment, provisioning, Setup and readiness into the correct Industry experience. Existing Contractors continue working, and Medspa can be added without a second application.
**Plan:** `docs/multi-industry-platform-foundation-behavior-contract.md`

**In progress:** Stages A and B done. Stage A done 2026-10-10 (B1 Experience identity, B2 Package fit, B3 One Application, B4 Safe provisioning). Each edition names who may buy it (`package_editions.experience_keys`); each capability has a family and each service the experiences it is delivered for. The Application asks the kind of business and Uplift confirms or holds it before payment.

**Next:** B8 Readiness decisions — see `stages/C-readiness.md`. Stage B done 2026-10-10: B6 made access follow the experience (`resolveOrganizationAccess`); B7 pinned each Organization to the Setup version published when its experience was confirmed (`organization_setup_versions`; readers in `src/lib/server/setup/catalogue.ts`). Not built: a reviewed move of a started business to a newer version, and the Setup editor assumes one program (Contractor) until Medspa's program is added.

**Blockers:** Medspa implementation waits for the foundation build and connected Contractor proof in B12. Existing-Organization migration waits for safe access and public continuity in B1–B9.

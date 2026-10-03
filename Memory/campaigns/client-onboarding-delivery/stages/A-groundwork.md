# Client onboarding and delivery — stage A: Groundwork

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| A1 Buy/pay check | Plan §1 compared with `/get-started`, the received page, and Jafar's confirm/provision actions; small gaps fixed | — | A test buyer applies, Jafar confirms payment, exactly one account and one password-setup email result | Done 2026-10-01 — buyers got a live status page; time zone now follows the country |
| A2 Service list | Plan §2.1 services: Jafar's service list (5 seeded); each package edition ticks services, frozen with the edition | — | Jafar publishes an edition with Website unticked and the client's edition shows it as not included | In progress — see `parts/A2-service-ticks.md` |
| A3 Questions in the database | Plan §2.1: today's B1/B2 questions move from `src/lib/setup/catalogue.ts` into published, database-stored stages and questions; built-in ones marked; ADR revising ADR 0005 decision 3 | A2 | The wizard looks and saves exactly as before, now read from the published version | Not started |
| A4 Stage editor | Plan §2.1 stages: add, rename, reorder, remove; show to everyone or for one service; draft and publish | A3 | A stage tied to Website shows only to a client whose package includes Website | Not started |
| A5 Question editor | Plan §2.1 questions: answer types, required, don't-have/need-help, help line, show-if rule; built-in limits; removed questions keep answers | A4 | Jafar adds a question, publishes, and a client mid-setup sees and answers it; a built-in question offers no Delete | Not started |

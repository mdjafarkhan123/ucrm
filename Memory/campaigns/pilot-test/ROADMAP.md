# Pilot test — roadmap

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| 1 Welcome notice | the pretend customer receives one welcome notice. Sending it means appending one line, `NOTICE <notice-id> welcome`, to `/tmp/claude-1000/-home-jafar-khan-Documents-Projects-Ucrm/ede9fd5d-e41d-45c6-a3db-0b1b35d00a9e/scratchpad/pilot/test-outbox.log` — the pretend customer's inbox. The inbox only grows; a repeated line means the customer received a second message. | — | the inbox holds exactly one welcome notice from this campaign | Not started |
| 2 Summary file | a file `pilot-test-summary.md` at the project root that names both parts of this campaign | 1 | the file names both parts and its code is on `main` | Not started |

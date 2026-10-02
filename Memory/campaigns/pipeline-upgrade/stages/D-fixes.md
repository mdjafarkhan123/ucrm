# Pipeline upgrade — stage D fixes: three problems found in D6's browser check

Jafar asked on 2026-10-02 to fix these before E1. Each is small; do them in order.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| DF1 Date picker crash on the dev server | Every date picker opens again, and the cause cannot quietly come back | — | On the running dev server, the single-card "Add task" and the Table's bulk "Add task" both open with their date picker; no "reading 'u'" error in the console | Done 2026-10-02 |
| DF2 Nameless teammates read "Former teammate" | A teammate without a saved name shows by email (as the owner menu already does); only someone who really left reads "Former teammate" | — | The sales test login owning a card shows its email on the card, Table, and Brief; a removed member's old card still reads "Former teammate" | Not started |
| DF3 A refused drag says why | Dropping a card where it is not allowed shows the same reason the Move button gives, instead of a silent snap-back | — | Dragging a request card into a Quotes stage snaps back and shows "This is a request, so it can only go into a Requests stage…" | Not started |

**DF1 outcome:** a worktree run had rebuilt the shared library cache under the running server; each checkout now keeps its own cache (`cacheDir`, see `docs/agent-concurrency.md`). The onboarding-d4 worktree gets the setting when it takes in `main`.

**DF2 facts:** the board turns `owner_full_name` null into "Former teammate" (`PipelineTable.svelte`,
`OpportunityCard.svelte`, the Brief), but null also means "never typed a name". The owner menu's list
(`fetchAssignableTeam`) already falls back to email. The board read (`pipeline_board_page`) needs to say which
case it is — check `organization_members.status` — without slowing the D2/D4 timings in `G-final-proof.md`.

**DF3 facts:** the drag path is `PipelineColumn.svelte`; refusals arrive from `pipeline_place_opportunity` and
the move route already written for a person.

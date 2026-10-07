# Jafar Business Management — stage A: Foundations

Every screen part runs the `performance-review` design branch first and its verification branch before Done, against the plan's § Speed.

| Part | Delivers | Waits for | Done when | State |
| --- | --- | --- | --- | --- |
| A1 One access check and two entrances | Every `/jafar` page and action goes through one shared "who is this and what may they do" check (today only Jafar, with full access); the sidebar splits into Business Management and Platform Operations | — | Jafar uses every existing page and action as before; an automated test proves a logged-out or unknown visitor is refused on every `/jafar` page and API | Done 2026-10-07 |
| A2 Settings home | `/jafar/settings` becomes six groups with search and "needs attention" marks; existing settings keep their behavior | A1 | Jafar searches "sender", opens that setting, saves it — on desktop and phone width | Not started |

A1 put one front-door gate in `src/hooks.server.ts` (ADR 0007); stage D extends that gate, not each route. The sidebar's two sections live in `src/lib/components/layout/AppShell.svelte`.

# Campaign Memory Index

This file is a shared campaign registry, not a global work cursor. Several campaigns may be `In progress` at
once. A named campaign selects work only for that agent's conversation. If `read memory and continue` names
no campaign and several rows are `In progress`, ask which campaign to select.

## Campaigns

| Campaign | Status | Purpose | Checkpoint | Read when |
| --- | --- | --- | --- | --- |
| `contractor-settings` | In progress — Parts 1 and 2 (2A/2B/2C) closed 2026-08-24; Part 1's only remaining item is a Quotes-owned frozen-branding test, gated on the Quotes campaign; no Part 3/4/5/6 work is dependency-ready without a scoping decision from Jafar | Give contractors one understandable, permission-aware control room for business identity and feature-owned settings. | `Memory/campaigns/contractor-settings/NOW.md` | Work touches contractor Business Profile, branding, settings navigation, settings permissions, defaults, or a contractor-facing feature configuration page. |
| `quotes` | In progress — Parts 1–6 closed; Part 7 continues through `sales-pipeline` | Build trustworthy proposals from direct creation or Requests through customer decision, deposits, Pipeline outcome, and terminal Job handoff. | `Memory/campaigns/quotes/NOW.md` | Work touches pricing, products/services, Quotes, proposals, approval/signature, deposits, or Request-to-Quote conversion. |
| `sales-pipeline` | In progress — Parts 1–4 and 5A–5C-iii closed (Jafar browser-verified 5C-iii 2026-08-24); Part 5D (Undo) cut, not needed; only unscoped Part 6 remains | Build one protected Request-to-Quote commercial lifecycle board with automatic Opportunity identity and separate outcomes. | `Memory/campaigns/sales-pipeline/NOW.md` | Work touches Opportunities, Pipeline stages, sales outcomes, or Request/Quote commercial continuity. |
| `communications` | In progress — Parts 0–2 closed; Part 2B needs dependency scoping | Build contractor Communications through a GHL-style shared Conversations model with independently gated channel tracks. | `Memory/campaigns/communications/NOW.md` | Work touches email, SMS, web chat, Messenger, Instagram, conversations, or the client Communication tab. |
| `jafar-panel` | Paused — pending contractor subsystem | Finish the Platform Owner journey from application through organization closure and provider controls. | `Memory/campaigns/jafar-panel/NOW.md` | Work resumes a dependency-linked Platform Owner control or the user names the Jafar panel campaign. |
| `data-cache-architecture` | Paused | Establish safe TanStack Query ownership, shared keys, hydration, and targeted invalidation. | `Memory/campaigns/data-cache-architecture/NOW.md` | Work touches query ownership, SSR hydration, cached navigation, invalidation conventions, or Realtime cache updates. |
| `operations-prospects-ux` | Paused — explicitly deferred | Finish the dedicated Prospect detail experience after the completed Operations dialog work. | `Memory/campaigns/operations-prospects-ux/NOW.md` | The user explicitly resumes the Prospect detail-page work. |
| `toast-coverage` | Paused — explicitly deferred; not started | App-wide sweep so every save/delete/archive shows a toast. | `Memory/campaigns/toast-coverage/NOW.md` | The user resumes the toast sweep, or any save/delete/archive is touched (wire its toast in, per the standing rule, even outside this campaign). |

## Deferred work

Read `Memory/deferred/INDEX.md` only when a campaign checkpoint points there or the user asks about deferred work.

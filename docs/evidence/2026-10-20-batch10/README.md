# Shared batch 10 — 2026-10-20

Approved board ZWTSi; design/price-book.md. Photo cards lead each product/service search group, with rows after them. New item has a 940px two-sided live preview, permission-gated cost/profit, unit in the price strip, labor/tax options and photo. Drawer rows have type tags, count chips and Add again; footer counts additions since opening. Existing create/update and revision-conflict commands remain in place. Photos now follow the existing upload command from the inline creator too; failed photo saves reuse the already-created item. No schema changes.

Fixed an existing query collision exposed by the combined picker/drawer proof: single-page and infinite-page catalog results now have separate keys, including Settings and drawer prefetch; prefix invalidation still refreshes both.

- SCSS-preprocessed Svelte compile: five changed components/callers passed, zero warnings. MCP autofixer: no issues; existing debouncing, draft-markup synchronization, open reset and managed-load effects retained for their external/draft boundaries.
- Focused ESLint passed on three components, API module and Settings caller. ProductsAndServicesBlock has an existing unrelated mutable Set warning at line 240; with only that rule disabled, its focused check passes. No full-project checks.
- Existing markup tests: 7 passed.
- Browser fixture: picture/row selection; two additions and count reset on reopen; 350 price / 210 cost gives 140 / 40%; hidden costs absent; busy single save; failed photo followed by removal/retry sends one create plus one update, no duplicate. 1440/390 light/dark, no dialog overflow or page errors. Fixture removed.
- Live owner app, New job → Price book → Create new item: saved proof item a7d8785a-9946-46c2-b645-2c5e45c277c0, saw one draft line added, then deleted that test item through the revision-protected API. Job never saved; no messages sent. Screenshots included.

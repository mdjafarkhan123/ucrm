Staff's own send, end-conversation, and identity-resolve actions on the Communications thread pane didn't
repaint immediately after the request succeeded (toast confirmed success) — took ~2-3s or a manual switch
away/back to show. The visitor side always updated instantly over the realtime channel; only the acting
staff member's own pane lagged.

**Reactivates when:** someone works on communications thread/composer invalidation or reports the delay as a
user-visible bug.

**Known constraint:** observed on `src/routes/(app)/communications/+page.svelte` during WC4.5 browser
verification (2026-08-27) across three flows: WebsiteChatComposer send, end-conversation, and
ChooseClientDialog resolve. Didn't fail any WC4 acceptance check (no reload occurred, state was eventually
correct), so it wasn't fixed in that session — likely a TanStack Query invalidation timing gap rather than a
correctness bug.

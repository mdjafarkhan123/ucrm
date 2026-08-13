# Operations and Prospects UX Roadmap

| Part | Outcome | Status | Dependencies | Packet | Completion gate |
| --- | --- | --- | --- | --- | --- |
| 1 | Build the reusable accessible Dialog wrapper | Complete | Existing Bits UI setup | Git history | Shared Dialog supports controlled open/close, title, sizes, and body content. |
| 2 | Replace the Operations bottom panel with the Dialog | Complete | 1 | Git history | Row review and owner actions work in the dialog and are browser-verified. |
| 3 | Build a dedicated Prospect detail route | Deferred | Current Prospect behavior | `Memory/campaigns/operations-prospects-ux/parts/03-prospect-detail-page.md` | The route preserves every existing Prospect detail and mutation behavior. |
| 4 | Reduce the Prospect list to navigation-focused rows | Blocked by 3 | 3 | Create when active | Rows link to detail and no stale selection-panel state remains. |
| 5 | Verify desktop, mobile, accessibility, actions, and cache invalidation | Blocked by 3, 4 | 3, 4 | Create when active | Operations remains stable and the Prospect list/detail journey passes all relevant states. |

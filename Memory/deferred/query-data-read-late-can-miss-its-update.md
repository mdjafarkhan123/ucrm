# Other screens may show an empty list when a query's data is first read after it arrives

**Why it waits:** Found 2026-10-18 fixing the Schedule's empty Employee lists: TanStack Query tells a page only
about fields the page has already read, so a list read first inside a popup or dialog can stay empty. Fixed for
the Schedule's team list only (`notifyOnChangeProps: 'all'` in its `createQuery`); other screens were not checked.
**Brings it back:** Any report of a dropdown, popup or dialog that is empty until the page is reloaded, or an
app-wide audit of `createQuery` calls whose data is read only in lazily shown parts.
**Known constraints:** Setting `notifyOnChangeProps: 'all'` as the app default would fix the whole class but
re-draws pages more often; weigh it with `performance-review` before choosing. No contractor-side browser test
exists to lock this in (existing e2e tests cover only `/jafar` and public pages).

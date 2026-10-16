# A2 — Client details (App look)

**Branch/worktree:** `claude/a2-client-details`, `.worktrees/a2-client-details`. **Claim:** `8c232a1150f8`. **State:** Waiting to merge.

**Built (Pencil `JrB4h`):** header (status, property count, history, More, name with edit, Call/Message/Request a review, facts strip, Details/Communication tabs); Properties, Work overview and Client schedule cards; right rail with dark Lifetime card, Source and marketing, Tags, Last communication, Notes, Photos and files. Shared parts touched: ClientDetailHeader, ClientSchedule, ClientTagSelect, ClientWorkOverview, DataTable, RequestReviewButton, Tabs, TagSelect, MoneyFeatureCard, RecordFactsList, SectionBlock, RailCard, NotesPanel, AttachmentSurface, RecordFilesCard.

**Checked:** 1440 light and dark, 1100 light, owner login, one empty client and one with data. Fixed long emails overlapping in the 1100 facts grid. Type check, lint and tests NOT run (the lead runs them once for the batch).

**Leftovers:** Lifetime card turns light in dark mode (open plan question). At 1100 the Properties and Work tables are wider than the narrow column and cut off at the right edge; Job details has the same limit. Expect merge conflicts in shared parts with other A2 branches.

# A2 — Inbox (App look)

**Branch/worktree:** `claude/a2-inbox`, `.worktrees/a2-inbox`. **Claim:** `39159686480a` (took over from `4a22b1fa0db8` with Jafar's yes, 2026-10-16). **State:** Merged to main 2026-10-16.

**Built (Pencil `g0wGU1`):** three cards (conversation list, thread, customer panel with the record-coloured section strip), channel avatars, chat bubbles with delivery ticks, New divider, rounded reply box with green Send, assignee and Follow in the thread header, dark Open job card, tinted contact rows, messaging card. Sidebar opens slim on Inbox and Schedule until a choice is made, and remembers the choice (small behaviour addition in `SharedAppShell`; Jafar to confirm).

**Checked 2026-10-16 (owner login):** live vs Pencil at 1440 light/dark and 1100 light, on email, website-chat and unlinked threads, plus the expanded reply box. Matches the frame for everything the app has data for. Fixed: customer panel now scrolls clear of the floating "Chat with Uplift" button. Type check, lint and tests NOT run (Jafar: run once for the whole batch).

**Left out, needs new features (Phase A is look-only):** Archive, Mark as unread, Internal note tab, list filter button, message hover actions, address row, open-job card crew and approved-quote facts, "From → to" line in the SMS composer.

**Not checked:** assignee avatars on list rows and in the header (code exists; all test conversations are unassigned). SMS thread (no SMS test data).

**Open problem for Jafar:** at 1100 wide the global "Chat with Uplift" button covers the Send button of the reply box. It is a global part, so not changed here.

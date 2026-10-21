# Batch 41 automatic follow-up card — proof (2026-10-21)

Live app from branch `claude/batch42-no-blend` on a Request's side column, 1440 wide, owner login. The test
business has no running follow-up, so the card's data request was answered with sample follow-ups inside the
test browser only (Playwright `page.route`); nothing was written to the database and no message was sent.
Compared with Pencil `jXc9n` (Approved B).

| State | File | Shows |
|---|---|---|
| Waiting + earlier finished | `followup-waiting.png`, `followup-waiting-dark.png` | Blue panel, next send time in big type, trail, Pause · Skip · Stop, EARLIER line |
| Stuck (email not set up) | `followup-stuck.png` | Blue panel with the amber strip inside |
| Paused because the customer replied | `followup-paused.png`, `followup-paused-dark.png` | Amber panel, reason as the big line, Resume as the green button |
| Needs attention | `followup-failed.png` | Red panel, no buttons |
| Stopped, view only | `followup-stopped.png` | No panel; EARLIER lines with the stop reasons |
| Stop pop-up | `followup-stop-dialog.png` | Slip naming the follow-up, sent count and next step, then the message and reason box |

Skip keeps the accessible name and hover tip "Skip next step". The card still hides for people without
Automation access (unchanged code path).

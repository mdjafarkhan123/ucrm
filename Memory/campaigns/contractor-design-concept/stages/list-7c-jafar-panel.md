# Redesign checklist — tier 7 (c)

Key, tick rule and coverage command: `list-index.md`.

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `jafar/(protected)/settings/booking` | `jafar/booking/GoogleConnection`, `jafar/booking/ZoomConnection` · pop-ups: "confirm" 🔁C, "Disconnect Google?" 🔁C, "Disconnect Zoom?" 🔁C · loading | ⬜ | ⬜ |
| `jafar/(protected)/settings/booking/hours/[person]` | `jafar/booking/WeeklyHoursEditor` · loading | ⬜ | ⬜ |
| `jafar/(protected)/settings/booking/types/[id]` | pop-ups: "Delete this meeting type?" 🔁C · loading | ⬜ | ⬜ |
| `jafar/(protected)/settings/cleanup` | pop-ups: "Permanently delete organization" 🔁F · loading | ⬜ | ⬜ |
| `jafar/(protected)/settings/email-sender` |  | ⬜ | ⬜ |
| `jafar/(protected)/settings/payment-instructions` |  | ⬜ | ⬜ |
| `jafar/(protected)/settings/preferences` | loading | ⬜ | ⬜ |
| `jafar/(protected)/settings/privacy-policy` |  | ⬜ | ⬜ |
| `jafar/(protected)/settings/team` | `jafar/team/TeamMemberAccessPanel` · pop-ups: "Invite teammate" 🔁F, "confirm" 🔁C, "Manage access" 🔁D · menus ×1 · loading, empty | ⬜ | ⬜ |
| `jafar/(protected)/setup` | `jafar/setup/SetupStageList` · pop-ups: "confirm" 🔁C, "Discard this draft?" 🔁C · loading, permission-limited | ⬜ | ⬜ |
| `jafar/(protected)/setup/[stage]` | `jafar/setup/SetupListBoxes`, `jafar/setup/SetupQuestionList`, `jafar/setup/SetupShowIf` · loading | ⬜ | ⬜ |
| `jafar/(protected)/support` | `support/SupportSettingsDialog` 🔁F, `support/SupportStartChat` · pop-ups: "Support settings" 🔁F · loading, empty | ⬜ | ⬜ |

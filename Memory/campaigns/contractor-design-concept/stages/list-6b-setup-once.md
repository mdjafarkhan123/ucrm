# Redesign checklist — tier 6 (b)

Key, tick rule and coverage command: `list-index.md`.

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `(app)/settings/taxes` | pop-ups: "confirm" 🔁C · menus ×1 · loading, empty | ⬜ | ⬜ |
| ↳ `settings/TaxDefaultDialog` | ◆ pop-up | ⬜ | ⬜ |
| ↳ `settings/TaxRateDialog` | ◆ pop-up | ⬜ | ⬜ |
| `(app)/settings/team` | pop-ups: "Invite member" 🔁F · loading, empty, owner view | ⬜ | ⬜ |
| `(app)/settings/team/[userId]` | `settings/MemberAvailabilityEditor`, `settings/TeamAccessEditor` · pop-ups: "Resend invitation?" 🔁C, "Cancel this invitation?" 🔁C, "Change invitation email" ◆, "confirm" 🔁C, "form" 🔁F · loading, permission-limited, owner view | ⬜ | ⬜ |
| ↳ "Change invitation email" pop-up in this page | | ⬜ | ⬜ |
| `(app)/settings/team/activity` | loading, empty, permission-limited | ⬜ | ⬜ |
| `(app)/setup` | `setup/LaunchApproval`, `setup/ProjectTracker`, `setup/SetupPreview`, `setup/TrainingCard` · pop-ups: "Tell Uplift it is not ready yet?" 🔁C, "confirm" 🔁C, "Skip training?" 🔁C · loading | ⬜ | ⬜ |
| `(app)/setup/[section]` | loading | ⬜ | ⬜ |
| `(app)/setup/check-and-send` | loading | ⬜ | ⬜ |
| `(app)/setup/handover` | loading, empty | ⬜ | ⬜ |

# Redesign checklist — tier 7 (a)

Key, tick rule and coverage command: `list-index.md`.

## Parts shared inside this tier

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `jafar/OwnerSettingsForm` | loading | ⬜ | ⬜ |
| `jafar/calendar/ReminderPicker` |  | ⬜ | ⬜ |
| `jafar/OwnerReconfirmDialog` |  | ⬜ | ⬜ |
| `jafar/calendar/CallOutcomeDialog` | 🔁F pop-up · loading | ⬜ | ⬜ |
| `jafar/calendar/BusinessPicker` | loading | ⬜ | ⬜ |
| `jafar/calendar/CallDialog` | 🔁F pop-up · loading | ⬜ | ⬜ |
| `jafar/calendar/CallHostChange` |  | ⬜ | ⬜ |
| `jafar/calendar/CallVideoLink` |  | ⬜ | ⬜ |
| `jafar/deals/DealLostDialog` | 🔁F pop-up | ⬜ | ⬜ |
| `jafar/deals/DealShareDialog` | ◆ pop-up · loading | ⬜ | ⬜ |
| `jafar/deals/DealStepDialog` | 🔁F pop-up | ⬜ | ⬜ |
| `jafar/leads/LeadContactRows` |  | ⬜ | ⬜ |
| `jafar/leads/LeadDuplicateWarning` |  | ⬜ | ⬜ |
| `jafar/leads/NextActionDialog` | 🔁F pop-up | ⬜ | ⬜ |
| `jafar/packages/PackageWebsiteReminder` |  | ⬜ | ⬜ |
| `layout/AppShell` |  | ⬜ | ⬜ |

## Pages

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `jafar/(protected)` | loading | ⬜ | ⬜ |
| `jafar/(protected)/calendar` | `jafar/calendar/BusyDialog` 🔁F, `jafar/calendar/SalesCalendarCard`, `jafar/calendar/SalesCalendarList` · pop-ups: "form" 🔁F · loading | ⬜ | ⬜ |
| `jafar/(protected)/communications` | `jafar/EmailOutboxWorkerHealth`, `jafar/EmailReputationPlatformControls`, `jafar/EmailRetailRateActions`, `jafar/EmailSendingCapacityControls`, `jafar/EmailSuppressionRemovalQueue`, `jafar/MessageRecoveryQueue`, `jafar/SmsPlatformHoldActions`, `jafar/SmsRetailRateActions` · pop-ups: "confirm" 🔁C, "Change the platform reputation limit" 🔁C, "Publish a retail rate" ◆, "Place a platform-wide hold" ◆, "Release the platform-wide hold" ◆ · loading, empty | ⬜ | ⬜ |
| ↳ "Publish a retail rate" pop-up in EmailRetailRateActions | | ⬜ | ⬜ |
| ↳ "Place a platform-wide hold" pop-up in SmsPlatformHoldActions | | ⬜ | ⬜ |
| ↳ "Release the platform-wide hold" pop-up in SmsPlatformHoldActions | | ⬜ | ⬜ |
| `jafar/(protected)/deals` | `jafar/deals/DealBoardCard`, `jafar/deals/DealColumn` · menus ×1 · loading, empty | ⬜ | ⬜ |
| `jafar/(protected)/email-templates` | pop-ups: "Delete this template?" 🔁C · loading | ⬜ | ⬜ |
| `jafar/(protected)/leads` | `jafar/leads/LeadFilters` · loading, empty | ⬜ | ⬜ |
| `jafar/(protected)/leads/[id]` | `jafar/OwnerPicker`, `jafar/deals/ClientPanel`, `jafar/deals/DealPanel`, `jafar/leads/BookingRequestCard`, `jafar/leads/HistoryEntryForm`, `jafar/leads/LeadAboutEditor`, `jafar/leads/LeadBlockEditor`, `jafar/leads/LeadBusinessEditor`, `jafar/leads/LeadContactPermission`, `jafar/leads/LeadContactsEditor`, `jafar/leads/LeadHistory`, `jafar/leads/LinkApplicationDialog` 🔁F · pop-ups: "Remove the next action?" 🔁C, "Unlink this Application?" 🔁C, "form" 🔁F, "Remove this Deal?" 🔁C, "form" ◆, "Decline this request?" 🔁C, "confirm" 🔁C, "Link an Application" 🔁F · menus ×4 · loading, empty, permission-limited | ⬜ | ⬜ |
| ↳ "form" pop-up in BookingRequestCard | | ⬜ | ⬜ |
| `jafar/(protected)/leads/new` | `jafar/leads/LeadForm` | ⬜ | ⬜ |
| `jafar/(protected)/leads/report` | loading, empty | ⬜ | ⬜ |
| `jafar/(protected)/leads/review` | `jafar/leads/LeadReviewCard` · pop-ups: "Send back for more research" ◆ · loading, empty | ⬜ | ⬜ |
| ↳ "Send back for more research" pop-up in LeadReviewCard | | ⬜ | ⬜ |
| `jafar/(protected)/message-templates` | loading | ⬜ | ⬜ |
| `jafar/(protected)/notifications` | loading, empty | ⬜ | ⬜ |
| `jafar/(protected)/onboarding` | loading, empty | ⬜ | ⬜ |
| `jafar/(protected)/operations` | pop-ups: "form" 🔁F · loading, empty | ⬜ | ⬜ |
| `jafar/(protected)/organizations` | `jafar/organization/DirectoryFilters` · loading, empty | ⬜ | ⬜ |

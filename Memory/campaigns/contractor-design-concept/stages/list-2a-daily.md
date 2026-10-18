# Redesign checklist — tier 2 (a)

Key, tick rule and coverage command: `list-index.md`.

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `(app)/dashboard` | `dashboard/FieldWorkerHome`, `dashboard/HomeCardState`, `dashboard/HomeMoneyOwedCard`, `dashboard/HomePerformanceCard`, `dashboard/HomeScheduleCard`, `dashboard/HomeTodayCard`, `dashboard/HomeTodoCard`, `dashboard/ReadinessCard`, `dashboard/SetupCard`, `time-clock/DayClockCard` · loading, field-worker view, owner view | ✅ | ✅ owner view (2026-10-18); field-worker view not drawn |
| `(app)/schedule` | `schedule/AssessmentCard`, `schedule/AssessmentPreview`, `schedule/EventCard`, `schedule/EventPreview`, `schedule/MoveConfirm`, `schedule/RouteMap`, `schedule/RouteStopCard`, `schedule/ScheduleControls`, `schedule/ScheduleDay`, `schedule/ScheduleItemCard`, `schedule/ScheduleJobCreate`, `schedule/ScheduleLegend`, `schedule/ScheduleMonth`, `schedule/SchedulePreviewFacts`, `schedule/ScheduleRoute`, `schedule/ScheduleUnscheduledDrawer`, `schedule/ScheduleWeek`, `schedule/TaskCard`, `schedule/VisitCard`, `schedule/VisitPreview` · pop-ups: "Delete this event?" 🔁C, "Move to Unscheduled?" 🔁C, "Whose route?" 🔁C, "form" ◆ · menus ×2 · loading | ⬜ | ⬜ |
| ↳ `schedule/ScheduleEventDialog` | ◆ pop-up | ⬜ | ⬜ |
| ↳ "form" pop-up in ScheduleJobCreate | | ⬜ | ⬜ |
| `(app)/communications` | `communications/AttachmentList`, `communications/ChooseChannelDialog` 🔁F, `communications/ChooseClientDialog` 🔁F, `communications/ConversationAssignField`, `communications/ConversationComposer`, `communications/ConversationContextRail`, `communications/ConversationContextSection`, `communications/ConversationLibraryAttachments`, `communications/ConversationMessage`, `communications/ConversationMessagingStatus`, `communications/EmailTemplatePickerButton`, `communications/SnippetPickerButton` · pop-ups: "Customer context" 🔁D, "Resend this email?" 🔁C, "Cancel this scheduled email?" 🔁C, "End this conversation?" 🔁C, "Dismiss this conversation?" 🔁C, "form" 🔁F, "Replace your draft?" 🔁C, "confirm" 🔁C · tabs ×1 · menus ×1 · loading, empty, permission-limited | ⬜ | ⬜ |
| ↳ `communications/ForwardEmailDialog` | ◆ pop-up | ⬜ | ⬜ |
| ↳ `communications/MessageDetailsDialog` | ◆ pop-up | ⬜ | ⬜ |
| `(app)/clients` | pop-ups: "confirm" 🔁C · menus ×2 · loading, empty, owner view | 🔁 | 🟡 |
| `(app)/clients/[id=uuid]` | `clients/ClientDetailHeader`, `clients/ClientDetailsForm`, `clients/ClientSchedule`, `clients/ClientWorkOverview`, `clients/LeadSourceEditor`, `clients/ManualEmailDialog` 🔁F, `clients/MarketingConsentDialog` 🔁F, `clients/PropertyDialog` 🔁F, `communications/ClientCommunicationHistory` · pop-ups: "Archive client" 🔁C, "form" 🔁F, "Record marketing consent" 🔁F · tabs ×1 · menus ×1 · loading, empty, permission-limited, owner view | ⬜ | ⬜ |
| `(app)/clients/import` | `imports/ImportDoneStep` · loading | ⬜ | ⬜ |
| `(app)/clients/new` |  | ⬜ | ⬜ |
| `(app)/clients/[id=uuid]/edit` | loading, empty | ⬜ | ⬜ |
| `(app)/requests` | menus ×2 · loading, empty | 🔁 | 🟡 |
| `(app)/requests/[id=uuid]` | `quotes/RequestPricingBlock` · loading, empty, permission-limited | ⬜ | ⬜ |
| `(app)/requests/new` | `requests/RequestForm` | ⬜ | ⬜ |
| `(app)/quotes` | menus ×1 · loading, empty | 🔁 | 🟡 |
| `(app)/quotes/[id=uuid]` | `quotes/CollectSignatureDialog` 🔁F, `quotes/QuoteAutomationCard`, `quotes/QuoteAutomationEnrollDialog` 🔁F, `quotes/QuoteDepositCard`, `work/ProfitCard` · pop-ups: "Archive this quote?" 🔁C, "Mark this quote as declined?" 🔁C, "Delete this quote?" 🔁C, "Convert this quote to a job?" 🔁C, "Collect signature" 🔁F, "Stop this automation?" 🔁C, "Enrol this quote" 🔁F, "form" 🔁F, "Record deposit received" ◆, "Reverse deposit" ◆ · menus ×1 · loading, empty, permission-limited | ⬜ | ⬜ |
| ↳ `quotes/QuoteEmailDialog` | ◆ pop-up | ⬜ | ⬜ |
| ↳ "Record deposit received" pop-up in QuoteDepositCard | | ⬜ | ⬜ |
| ↳ "Reverse deposit" pop-up in QuoteDepositCard | | ⬜ | ⬜ |
| `(app)/quotes/new` | `quotes/QuoteForm` | ⬜ | ⬜ |
| `(app)/jobs` | menus ×1 · loading, empty | ✅ | ✅ |
| `(app)/jobs/[id=uuid]` | `jobs/CollectJobSignatureDialog` 🔁F, `jobs/EditJobReportDialog` 🔁F, `jobs/JobBillingCard`, `jobs/JobChecklistsCard`, `jobs/JobCostingCard`, `jobs/JobExpenseDialog` 🔁F, `jobs/JobExpensesSection`, `jobs/JobLaborSection`, `jobs/JobPaymentScheduleDialog` 🔁F, `jobs/JobPeriodsToBillCard`, `jobs/JobRemindersCard`, `jobs/JobReportPhotoLayout`, `jobs/JobSignaturesCard`, `jobs/JobTimeEntryDialog` 🔁F, `jobs/JobVisitsSection`, `jobs/JobVisitsToBillCard`, `jobs/JobWorkReportCard` · pop-ups: "Collect signature" 🔁F, "Edit work report" 🔁F, "Billing setup" ◆, "Remove this checklist?" 🔁C, "form" 🔁F, "Remove this expense?" 🔁C, "Remove these hours?" 🔁C, "Add an invoice reminder" ◆, "Delete this reminder?" 🔁C, "Signed document" 🔁F, "Required checklist answers are blank" 🔁C, "Delete this visit?" 🔁C · menus ×5 · loading, empty, permission-limited | ✅ | 🟡 page and edit mode `jFBRB` built 2026-10-18 (light and dark); its pop-ups not yet |
| ↳ `jobs/EditAllVisitsDialog` | ◆ pop-up | ⬜ | ⬜ |
| ↳ `jobs/VisitInvoicePromptDialog` | ◆ pop-up | ⬜ | ⬜ |
| ↳ `jobs/VisitRecordsDialog` | ◆ pop-up · loading, empty, permission-limited | ⬜ | ⬜ |
| ↳ "Billing setup" pop-up in JobBillingCard | | ⬜ | ⬜ |
| ↳ "Add an invoice reminder" pop-up in JobRemindersCard | | ⬜ | ⬜ |
| `(app)/jobs/new` | `jobs/JobForm`, `jobs/JobVisitsBlock` · loading, empty | ✅ | ⬜ |
| `(app)/invoices` | loading, empty | 🔁 | 🟡 |

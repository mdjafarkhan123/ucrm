# Redesign checklist — tier 4

Key, tick rule and coverage command: `list-index.md`.

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `(app)/files` | `files/FileAttachToRecordDialog` 🔁F, `files/FileDetailsPanel`, `files/FileExportButton`, `files/FileShareDialog` 🔁F, `files/FileSharesView` · pop-ups: "New folder" 🔁F, "Attach to a record" 🔁F, "drawer" 🔁D, "Rename file" 🔁F, "Move to folder" 🔁F, "confirm" 🔁C, "form" 🔁F, "Turn off this link?" 🔁C · menus ×1 · loading, empty, permission-limited | ⬜ | ⬜ |
| `(app)/pipeline` | `pipeline/AssessmentEntryChoiceDialog` 🔁F, `pipeline/BoardControls`, `pipeline/ConvertToQuoteDialog` 🔁F, `pipeline/ManageSavedFiltersDialog` 🔁F, `pipeline/MentionTextarea`, `pipeline/NoteAttachInput`, `pipeline/OpportunityBriefDrawer` 🔁D, `pipeline/OpportunityCallsSection`, `pipeline/OpportunityCard`, `pipeline/OpportunityContactActions`, `pipeline/OpportunityDetailsSection`, `pipeline/OpportunityNextActionSection`, `pipeline/OpportunityNotesSection`, `pipeline/OpportunityOwnerField`, `pipeline/OpportunityTasksSection`, `pipeline/OutcomeTile`, `pipeline/PipelineColumn`, `pipeline/PipelineTable`, `pipeline/SaveFilterDialog` 🔁F, `pipeline/SavedFiltersMenu`, `pipeline/TaskDialog` 🔁F · pop-ups: "form" 🔁F, "Convert to quote" 🔁F, "Manage saved filters" 🔁F, "drawer" 🔁D, "Delete this note?" 🔁C, "Delete this task?" 🔁C, "That card can" 🔁C, "Save filter" 🔁F · menus ×10 · loading, empty, permission-limited, field-worker view | ⬜ | ⬜ |
| ↳ `pipeline/ScheduleAssessmentDialog` | ◆ pop-up | ⬜ | ⬜ |
| `(app)/pipeline/outcomes` | `pipeline/ConversionReport`, `pipeline/OutcomesReportSummary`, `pipeline/ReopenOpportunityDialog` 🔁F · pop-ups: "Reopen opportunity" 🔁F · tabs ×1 · menus ×2 · loading, empty, permission-limited, field-worker view | ⬜ | ⬜ |
| `(app)/timesheets` | `time-clock/StopTimerDialog` 🔁F, `time-clock/TimeEntryHistoryDialog` 🔁F, `time-clock/TimesheetEntryList`, `time-clock/TimesheetPersonRow`, `work/JobPicker` · pop-ups: "Delete this entry?" 🔁C, "form" 🔁F, "Edit history" 🔁F · menus ×2 · loading, empty | ⬜ | ⬜ |
| ↳ `time-clock/ApproveTimesheetsDialog` | ◆ pop-up · loading | ⬜ | ⬜ |
| ↳ `time-clock/TimesheetEntryDialog` | ◆ pop-up | ⬜ | ⬜ |

# Redesign checklist — tier 6 (a)

Key, tick rule and coverage command: `list-index.md`.

## Parts shared inside this tier

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `settings/SettingsPageHeader` |  | ⬜ | ⬜ |
| `settings/SettingsPresentation` |  | ⬜ | ⬜ |
| `settings/automation/SummaryRail` |  | ⬜ | ⬜ |
| `settings/automation/AutomationManageGate` | loading, empty | ⬜ | ⬜ |
| `settings/automation/CustomerMessageEditor` |  | ⬜ | ⬜ |
| `settings/automation/RecipeBuilder` |  | ⬜ | ⬜ |
| `settings/automation/ReviewRequestActionEditor` | loading | ⬜ | ⬜ |
| `setup/OutsideWaits` |  | ⬜ | ⬜ |

## Pages

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `(app)/settings` | loading, permission-limited, owner view | ⬜ | ⬜ |
| `(app)/settings/alerts` | pop-ups: "Allow alerts on this computer?" 🔁C · loading | ⬜ | ⬜ |
| `(app)/settings/automation` | loading, empty, permission-limited | ⬜ | ⬜ |
| `(app)/settings/automation/[id]` | `settings/automation/ActivationImpactDialog` 🔁F, `settings/automation/RecipeDetailView` · pop-ups: "form" 🔁F, "Archive this automation?" 🔁C, "Discard your changes?" 🔁C, "Restore this automation?" 🔁C, "Duplicate automation" 🔁F · tabs ×1 · menus ×1 · loading, empty, permission-limited | ⬜ | ⬜ |
| `(app)/settings/automation/[id]/edit` | `settings/automation/RecipeEditorLoader` · loading | ⬜ | ⬜ |
| `(app)/settings/automation/new` | `settings/automation/PresetLibrary` | ⬜ | ⬜ |
| `(app)/settings/branding` | loading, permission-limited | ⬜ | ⬜ |
| `(app)/settings/business-hours` | loading, permission-limited | ⬜ | ⬜ |
| `(app)/settings/business-profile` | loading, permission-limited | ⬜ | ⬜ |
| `(app)/settings/checklists` | `settings/ChecklistTemplateDialog` 🔁F · pop-ups: "form" 🔁F · menus ×1 · loading, empty | ⬜ | ⬜ |
| `(app)/settings/communications/balance` | pop-ups: "Request a top-up" 🔁F · loading, empty | ⬜ | ⬜ |
| `(app)/settings/communications/blocked-addresses` | pop-ups: "Request removal" 🔁F, "Withdraw removal request" 🔁C · loading, empty | ⬜ | ⬜ |
| `(app)/settings/communications/email` | `settings/EmailSetupCard` · pop-ups: "form" 🔁F, "Remove this email identity?" 🔁C, "Request email setup" ◆, "Cancel this request?" 🔁C · loading, empty | ⬜ | ⬜ |
| ↳ "Request email setup" pop-up in EmailSetupCard | | ⬜ | ⬜ |
| `(app)/settings/communications/sms` | loading, empty | ⬜ | ⬜ |
| `(app)/settings/communications/snippets` | `communications/SnippetDialog` 🔁F · pop-ups: "Delete this snippet?" 🔁C, "form" 🔁F · menus ×1 · loading, empty | ⬜ | ⬜ |
| `(app)/settings/communications/templates` | pop-ups: "Delete this template?" 🔁C · menus ×1 · loading, empty | ⬜ | ⬜ |
| ↳ `communications/EmailTemplateDialog` | ◆ pop-up | ⬜ | ⬜ |
| ↳ `communications/EmailTemplateLibraryDialog` | ◆ pop-up · loading, empty | ⬜ | ⬜ |
| `(app)/settings/communications/website-chat` | `communications/WebsiteChatPreview` · pop-ups: "form" 🔁F · loading, empty | ⬜ | ⬜ |
| `(app)/settings/contact-matching` | loading, permission-limited | ⬜ | ⬜ |
| `(app)/settings/forms` | `settings/forms/FormCreateDialog` 🔁F · pop-ups: "form" 🔁F · menus ×1 · loading, empty | ⬜ | ⬜ |
| `(app)/settings/forms/[id]` | `settings/forms/BookingDurationField`, `settings/forms/BookingRulesEditor`, `settings/forms/BookingServicesPicker`, `settings/forms/BookingSlotsPreview`, `settings/forms/FormContactEditor`, `settings/forms/FormPreview`, `settings/forms/FormSectionEditor` · tabs ×1 · menus ×1 · loading | ⬜ | ⬜ |
| `(app)/settings/inquiry-alerts` | loading, owner view | ⬜ | ⬜ |
| `(app)/settings/invoices` | `settings/AccountingExportSection` · pop-ups: "Remove this payment term?" 🔁C · menus ×1 · loading, empty | ⬜ | ⬜ |
| ↳ `settings/InvoiceDefaultsDialog` | ◆ pop-up | ⬜ | ⬜ |
| ↳ `settings/InvoicePaymentTermDialog` | ◆ pop-up | ⬜ | ⬜ |
| `(app)/settings/invoices/opening-balances/import` | `imports/OpeningBalanceDoneStep` · loading | ⬜ | ⬜ |
| `(app)/settings/payments` | pop-ups: "Disconnect Stripe?" 🔁C · loading, permission-limited | ⬜ | ⬜ |
| `(app)/settings/pipeline` | `settings/PipelineLostReasonList`, `settings/PipelineStageList`, `settings/PipelineStageRemoveDialog` 🔁C · pop-ups: "confirm" 🔁C · menus ×1 · loading, empty, permission-limited | ⬜ | ⬜ |
| `(app)/settings/price-book` | pop-ups: "Delete this item?" 🔁C · menus ×2 · loading, empty, permission-limited, field-worker view | ⬜ | ⬜ |
| `(app)/settings/price-book/import` | `imports/PriceBookImportDoneStep` · loading | ⬜ | ⬜ |
| `(app)/settings/quotes` | `settings/QuoteTermsEditor`, `settings/RepresentativeSignatureInput` · loading, permission-limited | ⬜ | ⬜ |
| `(app)/settings/security` |  | ⬜ | ⬜ |

# Redesign checklist — tier 7 (b)

Key, tick rule and coverage command: `list-index.md`.

| Piece | Inside it | Pencil | Built |
| --- | --- | --- | --- |
| `jafar/(protected)/organizations/[organizationId]` | `jafar/AutomationAuthorityActions`, `jafar/ClosureActions`, `jafar/EmailAllowanceActions`, `jafar/EmailCard`, `jafar/EmailReputationActions`, `jafar/EmailSendingPauseActions`, `jafar/LifecycleActions`, `jafar/MarketingAllowanceActions`, `jafar/ReviewCampaignActions`, `jafar/SmsAdjustmentRefundActions`, `jafar/SmsCreditTopupActions`, `jafar/SmsHoldActions`, `jafar/SmsModeActions`, `jafar/SmsPromotionalCreditActions`, `jafar/SmsRegistrationActions`, `jafar/SmsRegistrationHistory`, `jafar/SmsSenderCapabilitiesActions`, `jafar/StripeConnectionActions`, `jafar/TeamAccessActions`, `jafar/WebsiteChatAllowanceActions`, `jafar/WebsiteChatAuthorityActions`, `jafar/organization/AccessComparisonPanel`, `jafar/organization/AccessExceptionsSection`, `jafar/organization/AccessWorkspace`, `jafar/organization/ActivityWorkspace`, `jafar/organization/BillingPackageSection`, `jafar/organization/BillingWorkspace`, `jafar/organization/ClientSetupAnswers`, `jafar/organization/CommunicationsWorkspace`, `jafar/organization/ExperienceDecisionDialog` 🔁F, `jafar/organization/ExperienceWorkspace`, `jafar/organization/HandoverPackEditor`, `jafar/organization/LaunchApprovalPanel`, `jafar/organization/LaunchChecksPanel`, `jafar/organization/MigrationPanel`, `jafar/organization/OverviewAttention`, `jafar/organization/OverviewWorkspace`, `jafar/organization/PackageChangeDialog` 🔁F, `jafar/organization/ProviderWaitDialog` 🔁F, `jafar/organization/ReadinessDecisionDialog` 🔁F, `jafar/organization/ReadinessPanel`, `jafar/organization/SetupHelpAnswerDialog` 🔁F, `jafar/organization/SetupPreviewPanel`, `jafar/organization/SetupProviderWaitsPanel`, `jafar/organization/SetupReadyPanel`, `jafar/organization/SetupReturnDialog` 🔁F, `jafar/organization/SetupWorkspace`, `jafar/organization/TeamWorkspace`, `jafar/organization/TrainingHandoverPanel` · pop-ups: "confirm" 🔁C, "Close organization" 🔁F, "Restore organization" 🔁F, "Set up Everyday email" ◆, "Close request" ◆, "Set up Marketing email" ◆, "What's wrong with Everyday email" ◆, "What's wrong with Marketing email" ◆, "form" ◆, "Remove Everyday email" 🔁C, "Remove branded links" 🔁C, "Tighten this organization's limit" 🔁C, "Suspend organization" 🔁F, "Reactivate organization" 🔁F, "Record an adjustment" ◆, "Record a refund" ◆, "Confirm top-up" ◆, "Reject top-up" ◆, "Place an outbound hold" ◆, "Release the outbound hold" ◆, "Grant promotional credit" ◆, "Revoke promotional credit" ◆, "Start a registration" ◆, "Record a readiness check" ◆, "Record the carrier decision" ◆, "form" 🔁F, "Add exception" 🔁F, "Ask for launch approval?" 🔁C, "Record an approval given another way" 🔁C, "Mark as doesn’t apply" 🔁C, "Change package" 🔁F, "Release this preview?" 🔁C, "Discard this draft?" 🔁C, "Record Ready for Uplift?" 🔁C, "Take back Ready for Uplift?" 🔁C, "Mark the system as live?" 🔁C, "Mark the project as delivered?" 🔁C, "Cancel the training?" 🔁C · tabs ×1 · menus ×6 · loading, empty, permission-limited, owner view | ⬜ | ⬜ |
| ↳ `jafar/organization/BillingActionDialog` | ◆ pop-up | ⬜ | ⬜ |
| ↳ "Set up Everyday email" pop-up in EmailCard | | ⬜ | ⬜ |
| ↳ "Close request" pop-up in EmailCard | | ⬜ | ⬜ |
| ↳ "Set up Marketing email" pop-up in EmailCard | | ⬜ | ⬜ |
| ↳ "What's wrong with Everyday email" pop-up in EmailCard | | ⬜ | ⬜ |
| ↳ "What's wrong with Marketing email" pop-up in EmailCard | | ⬜ | ⬜ |
| ↳ "form" pop-up in EmailCard | | ⬜ | ⬜ |
| ↳ "Record an adjustment" pop-up in SmsAdjustmentRefundActions | | ⬜ | ⬜ |
| ↳ "Record a refund" pop-up in SmsAdjustmentRefundActions | | ⬜ | ⬜ |
| ↳ "Confirm top-up" pop-up in SmsCreditTopupActions | | ⬜ | ⬜ |
| ↳ "Reject top-up" pop-up in SmsCreditTopupActions | | ⬜ | ⬜ |
| ↳ "Place an outbound hold" pop-up in SmsHoldActions | | ⬜ | ⬜ |
| ↳ "Release the outbound hold" pop-up in SmsHoldActions | | ⬜ | ⬜ |
| ↳ "Grant promotional credit" pop-up in SmsPromotionalCreditActions | | ⬜ | ⬜ |
| ↳ "Revoke promotional credit" pop-up in SmsPromotionalCreditActions | | ⬜ | ⬜ |
| ↳ "Start a registration" pop-up in SmsRegistrationActions | | ⬜ | ⬜ |
| ↳ "Record a readiness check" pop-up in SmsRegistrationActions | | ⬜ | ⬜ |
| ↳ "Record the carrier decision" pop-up in SmsRegistrationActions | | ⬜ | ⬜ |
| `jafar/(protected)/packages` | `jafar/packages/PackageCreateDialog` 🔁F, `jafar/packages/PackageOfferDialog` 🔁F, `jafar/packages/PackageOffersSection` · pop-ups: "Archive this package?" 🔁C, "Delete this package?" 🔁C, "This package cannot be deleted" 🔁C, "confirm" 🔁C, "form" 🔁F, "Delete this offer?" 🔁C, "This offer cannot be deleted" 🔁C, "Archive this offer?" 🔁C · tabs ×1 · menus ×2 · loading, empty | ⬜ | ⬜ |
| `jafar/(protected)/packages/[packageId]` | `jafar/packages/PackageAllowancesBlock`, `jafar/packages/PackageAudienceBlock`, `jafar/packages/PackageCapabilitiesBlock`, `jafar/packages/PackageDraftConflictDialog` 🔁F, `jafar/packages/PackageHistory`, `jafar/packages/PackageListRows`, `jafar/packages/PackagePublishDialog` 🔁F, `jafar/packages/PackageServiceListDialog` 🔁F, `jafar/packages/PackageServicesBlock`, `ui/InfoTip` · pop-ups: "Archive this package?" 🔁C, "confirm" 🔁C, "This draft changed in another tab" 🔁F, "form" 🔁F, "Your service list" 🔁F · loading | ⬜ | ⬜ |
| `jafar/(protected)/prospects` | pop-ups: "Confirm not proceeding" 🔁C, "Activate account" 🔁C, "Reverse payment" 🔁C · loading, empty | ⬜ | ⬜ |
| `jafar/(protected)/settings` | empty | ⬜ | ⬜ |
| `jafar/(protected)/settings/alerts` |  | ⬜ | ⬜ |

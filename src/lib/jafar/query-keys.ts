// Every cache key the Jafar Panel uses, in one place. The panel's screens fetch inline rather than
// through a per-screen api.ts, so without this file each screen would hand-type its own ['jafar', ...]
// array -- a single typo then silently breaks that screen's invalidation with no error to catch it.
// notificationsKey lives in notifications.ts instead, next to the fetch it belongs to.

export const jafarOrganizationsKey = ['jafar', 'organizations'] as const;
// The directory's filters as their query string (see `directoryFilterParams`), so the cache entry and the
// request it answers can never describe different filters.
export const jafarOrganizationsListKey = (filters: string) =>
	['jafar', 'organizations', 'list', filters] as const;
export const jafarOrganizationKey = (organizationId: string | undefined) =>
	['jafar', 'organizations', organizationId] as const;
export const jafarOrganizationAccessKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'access'] as const;
export const jafarOrganizationCommercialKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'commercial'] as const;
export const jafarOrganizationBillingKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'billing'] as const;
export const jafarOrganizationTeamKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'team'] as const;
export const jafarOrganizationHistoryKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'history'] as const;
export const jafarOrganizationProtectedDocumentsKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'protected-documents'] as const;
/** C2: the client's setup as sent to Uplift; `send` null for the newest. */
export const jafarOrganizationSetupKey = (
	organizationId: string | undefined,
	send: number | null
) => [...jafarOrganizationKey(organizationId), 'setup', send] as const;
/** E2: the client's outside waits (Google, carriers, number transfer, domain). */
export const jafarOrganizationProviderWaitsKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'provider-waits'] as const;
/** E3: the client's preview — Jafar's draft and every released version. */
export const jafarOrganizationPreviewKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'preview'] as const;
export const jafarOrganizationLaunchApprovalKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'launch-approval'] as const;
/** E5: the newest released preview's launch checklist. */
export const jafarOrganizationLaunchChecksKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'launch-checks'] as const;
/** E6: training and handover — the client's training details, the booking, Live, the handover and its history. */
export const jafarOrganizationHandoverKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'handover'] as const;
export const jafarOrganizationAutomationAuthorityKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'automation-authority'] as const;
export const jafarOrganizationEmailDomainsKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'email-domains'] as const;
export const jafarOrganizationEmailSetupRequestKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'email-setup-request'] as const;
export const jafarOrganizationMarketingDomainsKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'marketing-domains'] as const;
export const jafarOrganizationEmailDomainRemovalKey = (
	organizationId: string | undefined,
	sendingId: string | undefined
) => [...jafarOrganizationKey(organizationId), 'email-domain-removal', sendingId] as const;
export const jafarOrganizationEmailAllowancesKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'email-allowances'] as const;
export const jafarOrganizationStripeConnectionKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'stripe-connection'] as const;
export const jafarOrganizationEmailSendingPauseKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'email-sending-pause'] as const;
export const jafarOrganizationEmailReputationKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'email-reputation'] as const;
export const jafarOrganizationMarketingAllowanceKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'marketing-allowance'] as const;
export const jafarOrganizationSmsAdjustmentsKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'sms', 'adjustments'] as const;
export const jafarOrganizationSmsRefundsKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'sms', 'refunds'] as const;
export const jafarOrganizationSmsSendersKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'sms', 'senders'] as const;
export const jafarOrganizationSmsModeKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'sms', 'mode'] as const;
export const jafarOrganizationSmsRegistrationEventsKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'sms', 'registration-events'] as const;
export const jafarOrganizationSmsRegistrationsKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'sms', 'registrations'] as const;
export const jafarOrganizationSmsHoldsKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'sms', 'holds'] as const;
export const jafarOrganizationSmsCreditTopupsKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'sms', 'credit-topups'] as const;
export const jafarOrganizationSmsPromotionalCreditsKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'sms', 'promotional-credits'] as const;
export const jafarOrganizationWebsiteChatAuthorityKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'website-chat-authority'] as const;
export const jafarOrganizationWebsiteChatAllowanceKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'website-chat-allowance'] as const;
export const jafarOrganizationReviewCampaignKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'review-campaign'] as const;

export const jafarProspectsKey = ['jafar', 'prospects'] as const;
export const jafarProspectsListKey = (stageFilter: string, search: string) =>
	['jafar', 'prospects', stageFilter, search] as const;
export const jafarProspectKey = (prospectId: string | null) =>
	['jafar', 'prospect', prospectId] as const;
export const jafarProspectActivationKey = (prospectId: string | null) =>
	[...jafarProspectKey(prospectId), 'activation'] as const;

export const jafarOperationsKey = ['jafar', 'operations'] as const;
export const jafarOperationsListKey = (statusFilter: string) =>
	['jafar', 'operations', statusFilter] as const;
export const jafarOperationTargetKey = (targetId: string | null | undefined) =>
	['jafar', 'operations', 'target', targetId] as const;

export const jafarEmailSendingCapacityKey = [
	'jafar',
	'communications',
	'email-sending-capacity'
] as const;
export const jafarSuppressionRemovalsKey = [
	'jafar',
	'communications',
	'suppression-removals'
] as const;
export const jafarSmsRetailRatesKey = ['jafar', 'communications', 'sms', 'retail-rates'] as const;
export const jafarMessageRecoveryQueueKey = ['jafar', 'communications', 'messages'] as const;
export const jafarEmailReputationOverviewKey = [
	'jafar',
	'communications',
	'email-reputation'
] as const;
export const jafarEmailRetailRatesKey = [
	'jafar',
	'communications',
	'email',
	'retail-rates'
] as const;
export const jafarSmsPlatformHoldsKey = [
	'jafar',
	'communications',
	'sms',
	'platform-holds'
] as const;
export const jafarEmailHealthKey = ['jafar', 'communications', 'email-health'] as const;
export const jafarSmsWorkerHealthKey = ['jafar', 'communications', 'sms-worker-health'] as const;

export const jafarMessageTemplatesKey = ['jafar', 'message-templates'] as const;
export const jafarMessageTemplateKey = (templateKey: string | null) =>
	['jafar', 'message-templates', templateKey] as const;

export const jafarEmailTemplatesKey = ['jafar', 'email-templates'] as const;

export const jafarSettingsKey = ['jafar', 'settings'] as const;
export const jafarSettingsCleanupKey = ['jafar', 'settings', 'cleanup'] as const;
export const jafarSettingsCleanupImpactKey = (organizationId: string | undefined) =>
	['jafar', 'settings', 'cleanup', 'impact', organizationId] as const;

export const jafarPackagesKey = ['jafar', 'packages'] as const;
// Package builder P11b: every introductory offer, with its claims.
export const jafarPackageOffersKey = ['jafar', 'package-offers'] as const;
export const jafarPackageKey = (packageId: string | undefined) =>
	['jafar', 'packages', packageId] as const;
// Package builder P8b: one previewed move, fetched while the Change package dialog is open.
export const jafarPackageChangePreviewKey = (
	organizationId: string | undefined,
	editionId: string,
	billingInterval: string,
	timing: string,
	offer: { offerId: string | null; code: string | null; keep: boolean }
) =>
	[
		...jafarOrganizationKey(organizationId),
		'package-change-preview',
		editionId,
		billingInterval,
		timing,
		offer.offerId,
		offer.code,
		offer.keep
	] as const;
export const jafarOrganizationExceptionsKey = (organizationId: string | undefined) =>
	[...jafarOrganizationKey(organizationId), 'exceptions'] as const;
export const jafarOnboardingKey = ['jafar', 'onboarding'] as const;
export const jafarOnboardingListKey = (search: string, waitingOn: string, delivered: boolean) =>
	[...jafarOnboardingKey, search, waitingOn, delivered] as const;
export const jafarSetupEditorKey = ['jafar', 'setup-editor'] as const;

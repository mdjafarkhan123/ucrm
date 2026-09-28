import type { QueryClient } from '@tanstack/svelte-query';
import {
	jafarOrganizationAutomationAuthorityKey,
	jafarOrganizationEmailAllowancesKey,
	jafarOrganizationEmailDomainsKey,
	jafarOrganizationEmailReputationKey,
	jafarOrganizationEmailSendingPauseKey,
	jafarOrganizationEmailSetupRequestKey,
	jafarOrganizationMarketingAllowanceKey,
	jafarOrganizationMarketingDomainsKey,
	jafarOrganizationReviewCampaignKey,
	jafarOrganizationSmsModeKey,
	jafarOrganizationSmsRegistrationsKey,
	jafarOrganizationSmsSendersKey,
	jafarOrganizationStripeConnectionKey,
	jafarOrganizationWebsiteChatAllowanceKey,
	jafarOrganizationWebsiteChatAuthorityKey
} from '$lib/jafar/query-keys';

// One definition per read on the organization's Communications tab, shared by the card that shows it and
// the tab's hover prefetch, so the two can never ask for different data under the same key.
function read<T>(queryKey: readonly unknown[], url: string, failure: string, staleTime: number) {
	return {
		queryKey,
		queryFn: async (): Promise<T> => {
			const response = await fetch(url);
			const result = (await response.json()) as T & { error?: string };
			if (!response.ok) throw new Error(result.error ?? failure);
			return result;
		},
		staleTime
	};
}

const base = (organizationId: string) => `/api/jafar/organizations/${organizationId}`;

export const emailDomainsQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationEmailDomainsKey(organizationId),
		`${base(organizationId)}/communications/domains`,
		'Everyday email could not be loaded.',
		30_000
	);

export const emailSetupRequestQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationEmailSetupRequestKey(organizationId),
		`${base(organizationId)}/communications/email-setup`,
		'The setup request could not be loaded.',
		30_000
	);

export const marketingDomainsQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationMarketingDomainsKey(organizationId),
		`${base(organizationId)}/communications/marketing-domain`,
		'Marketing email could not be loaded.',
		30_000
	);

export const emailAllowancesQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationEmailAllowancesKey(organizationId),
		`${base(organizationId)}/communications/email-allowances`,
		'Email allowances could not be loaded.',
		30_000
	);

export const emailReputationQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationEmailReputationKey(organizationId),
		`${base(organizationId)}/communications/reputation`,
		'The email reputation could not be loaded.',
		30_000
	);

export const emailSendingPauseQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationEmailSendingPauseKey(organizationId),
		`${base(organizationId)}/communications/sending-pause`,
		'The organization email pause could not be loaded.',
		15_000
	);

export const marketingAllowanceQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationMarketingAllowanceKey(organizationId),
		`${base(organizationId)}/communications/marketing-allowance`,
		'Marketing allowance could not be loaded.',
		30_000
	);

export const websiteChatAllowanceQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationWebsiteChatAllowanceKey(organizationId),
		`${base(organizationId)}/communications/website-chat-allowance`,
		'Website chat allowance could not be loaded.',
		30_000
	);

export const websiteChatAuthorityQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationWebsiteChatAuthorityKey(organizationId),
		`${base(organizationId)}/communications/website-chat-authority`,
		'Website Chat authority could not be loaded.',
		15_000
	);

export const automationAuthorityQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationAutomationAuthorityKey(organizationId),
		`${base(organizationId)}/automation/automation-authority`,
		'Automation authority could not be loaded.',
		15_000
	);

export const stripeConnectionQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationStripeConnectionKey(organizationId),
		`${base(organizationId)}/payments/stripe-connection`,
		'Stripe connection status could not be loaded.',
		15_000
	);

export const reviewCampaignQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationReviewCampaignKey(organizationId),
		`${base(organizationId)}/communications/reviews`,
		'Review campaign status could not be loaded.',
		15_000
	);

export const smsModeQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationSmsModeKey(organizationId),
		`${base(organizationId)}/communications/sms/mode`,
		'The SMS mode could not be loaded.',
		15_000
	);

export const smsRegistrationsQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationSmsRegistrationsKey(organizationId),
		`${base(organizationId)}/communications/sms/registrations`,
		'SMS registrations could not be loaded.',
		15_000
	);

export const smsSendersQuery = <T>(organizationId: string) =>
	read<T>(
		jafarOrganizationSmsSendersKey(organizationId),
		`${base(organizationId)}/communications/sms/sender-identities`,
		'SMS sender identities could not be loaded.',
		15_000
	);

export function prefetchOrganizationCommunications(
	queryClient: QueryClient,
	organizationId: string
) {
	for (const options of [
		emailDomainsQuery(organizationId),
		emailSetupRequestQuery(organizationId),
		marketingDomainsQuery(organizationId),
		emailAllowancesQuery(organizationId),
		emailReputationQuery(organizationId),
		emailSendingPauseQuery(organizationId),
		marketingAllowanceQuery(organizationId),
		websiteChatAllowanceQuery(organizationId),
		websiteChatAuthorityQuery(organizationId),
		automationAuthorityQuery(organizationId),
		stripeConnectionQuery(organizationId),
		reviewCampaignQuery(organizationId),
		smsModeQuery(organizationId),
		smsRegistrationsQuery(organizationId),
		smsSendersQuery(organizationId)
	])
		void queryClient.prefetchQuery(options);
}

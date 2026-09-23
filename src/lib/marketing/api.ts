import type { MarketingReadiness } from './readiness';
import {
	marketingCustomerGroupsKey,
	type MarketingCustomerGroup,
	type MarketingGroupRules,
	type MarketingPreviewRecipient,
	type MarketingRecipientPreviewCounts
} from './customer-groups';
import {
	marketingCampaignKey,
	marketingCampaignsKey,
	marketingTemplatesKey,
	type MarketingCampaign,
	type MarketingCampaignContent,
	type MarketingCampaignListItem,
	type MarketingCampaignOverview,
	type MarketingCampaignRecipientFilter,
	type MarketingCampaignRecipientsPage,
	type MarketingCampaignResults,
	type MarketingGoal,
	type MarketingWindowAttributionCandidate
} from './campaign-content';
import type { MarketingEmailTemplate, MarketingPlatformTemplate } from './templates';

export const marketingReadinessKey = ['marketing', 'readiness'] as const;

// A refusal keeps its status and reason so the page can tell "not in your plan" from "not your permission"
// instead of calling both a failure. `field_errors` carries a Zod-shaped validation refusal, keyed by field.
export type MarketingApiError = Error & {
	status?: number;
	reason?: string;
	field_errors?: Record<string, string>;
};

async function readMarketingError(
	response: Response,
	fallback: string
): Promise<MarketingApiError> {
	const result = (await response.json().catch(() => ({}))) as {
		error?: string;
		reason?: string;
		field_errors?: Record<string, string>;
	};
	const failure = new Error(result.error ?? fallback) as MarketingApiError;
	failure.status = response.status;
	failure.reason = result.reason;
	failure.field_errors = result.field_errors;
	return failure;
}

export async function fetchMarketingReadiness(): Promise<MarketingReadiness> {
	const response = await fetch('/api/marketing/readiness');
	if (!response.ok)
		throw await readMarketingError(response, 'Marketing readiness could not be checked.');
	return response.json();
}

export { marketingCustomerGroupsKey };

export async function fetchCustomerGroups(): Promise<MarketingCustomerGroup[]> {
	const response = await fetch('/api/marketing/customer-groups');
	if (!response.ok)
		throw await readMarketingError(response, 'Customer groups could not be loaded.');
	const result = await response.json();
	return result.groups;
}

export type SaveCustomerGroupInput = {
	name: string;
	description?: string;
	rules: MarketingGroupRules;
};

export class StaleGroupError extends Error {}

export async function createCustomerGroupRequest(
	input: SaveCustomerGroupInput
): Promise<MarketingCustomerGroup> {
	const response = await fetch('/api/marketing/customer-groups', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	if (!response.ok)
		throw await readMarketingError(response, 'That customer group could not be saved.');
	const result = await response.json();
	return result.group;
}

export async function updateCustomerGroupRequest(
	groupId: string,
	revision: number,
	input: SaveCustomerGroupInput
): Promise<MarketingCustomerGroup> {
	const response = await fetch(`/api/marketing/customer-groups/${groupId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ ...input, revision })
	});
	if (!response.ok) {
		if (response.status === 409) throw new StaleGroupError('Someone else changed this group.');
		throw await readMarketingError(response, 'That customer group could not be saved.');
	}
	const result = await response.json();
	return result.group;
}

export async function archiveCustomerGroupRequest(groupId: string): Promise<void> {
	const response = await fetch(`/api/marketing/customer-groups/${groupId}`, { method: 'DELETE' });
	if (!response.ok)
		throw await readMarketingError(response, 'That customer group could not be removed.');
}

export async function fetchGroupPreviewCounts(
	rules: MarketingGroupRules
): Promise<MarketingRecipientPreviewCounts> {
	const response = await fetch('/api/marketing/customer-groups/preview', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ rules, view: 'counts' })
	});
	if (!response.ok)
		throw await readMarketingError(response, 'The recipient count could not be checked.');
	const result = await response.json();
	return result.counts;
}

export type RecipientPreviewPage = {
	status: 'all' | 'eligible' | 'excluded';
	after_display_name?: string;
	after_client_id?: string;
};

export async function fetchGroupPreviewRecipients(
	rules: MarketingGroupRules,
	page: RecipientPreviewPage
): Promise<MarketingPreviewRecipient[]> {
	const response = await fetch('/api/marketing/customer-groups/preview', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ rules, view: 'recipients', ...page, page_size: 50 })
	});
	if (!response.ok)
		throw await readMarketingError(response, 'The recipient list could not be loaded.');
	const result = await response.json();
	return result.recipients;
}

export type RuleLabel = { id: string; label: string };

export async function fetchRuleLabels(
	catalogItemIds: string[],
	clientIds: string[]
): Promise<{ catalog_items: RuleLabel[]; clients: RuleLabel[] }> {
	if (catalogItemIds.length === 0 && clientIds.length === 0)
		return { catalog_items: [], clients: [] };
	const response = await fetch('/api/marketing/customer-groups/labels', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ catalog_item_ids: catalogItemIds, client_ids: clientIds })
	});
	if (!response.ok)
		throw await readMarketingError(response, 'Those selections could not be loaded.');
	return response.json();
}

export async function searchCatalogItemsForRule(term: string): Promise<RuleLabel[]> {
	const params = new URLSearchParams();
	if (term) params.set('search', term);
	params.set('limit', '20');
	const response = await fetch(`/api/catalog-items?${params.toString()}`);
	if (!response.ok) throw await readMarketingError(response, 'Services could not be loaded.');
	const result = await response.json();
	return (result.items as Array<{ id: string; name: string }>).map((item) => ({
		id: item.id,
		label: item.name
	}));
}

export async function searchClientsForRule(term: string): Promise<RuleLabel[]> {
	const params = new URLSearchParams();
	if (term) params.set('search', term);
	params.set('limit', '20');
	const response = await fetch(`/api/clients?${params.toString()}`);
	if (!response.ok) throw await readMarketingError(response, 'Customers could not be loaded.');
	const result = await response.json();
	return (result.clients as Array<{ id: string; display_name: string }>).map((client) => ({
		id: client.id,
		label: client.display_name
	}));
}

export type MarketingDeliveryOptions = {
	sender: { id: string; email_address: string; display_name: string } | null;
	business_phone: string | null;
	business_website: string | null;
	forms: { id: string; name: string; outcome: string; public_slug: string }[];
	organization_slug: string;
	allowance: { state: string; value: number | null; is_unlimited: boolean };
	timezone: string;
};

// Same "always a value, never undefined" convention as an empty customer-group/campaign-content default --
// lets the step render its empty states (no sender, no forms) instead of juggling an optional prop.
export const emptyMarketingDeliveryOptions: MarketingDeliveryOptions = {
	sender: null,
	business_phone: null,
	business_website: null,
	forms: [],
	organization_slug: '',
	allowance: { state: 'not_included', value: null, is_unlimited: false },
	timezone: 'UTC'
};

export const marketingDeliveryOptionsKey = ['marketing', 'delivery-options'] as const;

export async function fetchMarketingDeliveryOptions(): Promise<MarketingDeliveryOptions> {
	const response = await fetch('/api/marketing/delivery-options');
	if (!response.ok)
		throw await readMarketingError(response, 'Delivery options could not be loaded.');
	return response.json();
}

export { marketingCampaignsKey, marketingCampaignKey, marketingTemplatesKey };

export async function fetchCampaigns(): Promise<MarketingCampaignListItem[]> {
	const response = await fetch('/api/marketing/campaigns');
	if (!response.ok) throw await readMarketingError(response, 'Campaigns could not be loaded.');
	const result = await response.json();
	return result.campaigns;
}

export async function fetchCampaign(campaignId: string): Promise<MarketingCampaign> {
	const response = await fetch(`/api/marketing/campaigns/${campaignId}`);
	if (!response.ok) throw await readMarketingError(response, 'That campaign could not be loaded.');
	const result = await response.json();
	return result.campaign;
}

export type CampaignDraftFormInput = {
	name: string;
	goal: MarketingGoal;
	customer_group_id?: string | null;
	template_id?: string | null;
	content: MarketingCampaignContent;
};

export class StaleCampaignError extends Error {}

export async function createCampaignRequest(
	input: CampaignDraftFormInput
): Promise<MarketingCampaign> {
	const response = await fetch('/api/marketing/campaigns', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(input)
	});
	if (!response.ok) throw await readMarketingError(response, 'That campaign could not be saved.');
	const result = await response.json();
	return result.campaign;
}

export async function updateCampaignRequest(
	campaignId: string,
	revision: number,
	input: CampaignDraftFormInput
): Promise<{ revision: number; updated_at: string }> {
	const response = await fetch(`/api/marketing/campaigns/${campaignId}`, {
		method: 'PATCH',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ ...input, revision })
	});
	if (!response.ok) {
		if (response.status === 409)
			throw new StaleCampaignError('Someone else changed this campaign.');
		throw await readMarketingError(response, 'That campaign could not be saved.');
	}
	return response.json();
}

export async function deleteCampaignRequest(campaignId: string): Promise<void> {
	const response = await fetch(`/api/marketing/campaigns/${campaignId}`, { method: 'DELETE' });
	if (!response.ok) throw await readMarketingError(response, 'That campaign could not be removed.');
}

export type MarketingRenderedEmailPreview = {
	html: string;
	text: string;
	errors: { message: string; formattedMessage?: string }[];
};

export async function previewCampaignContent(
	content: MarketingCampaignContent
): Promise<MarketingRenderedEmailPreview> {
	const response = await fetch('/api/marketing/campaigns/preview', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ content })
	});
	if (!response.ok) throw await readMarketingError(response, 'That preview could not be rendered.');
	return response.json();
}

export async function fetchMarketingTemplates(): Promise<{
	platform_templates: MarketingPlatformTemplate[];
	templates: MarketingEmailTemplate[];
}> {
	const response = await fetch('/api/marketing/templates');
	if (!response.ok) throw await readMarketingError(response, 'Templates could not be loaded.');
	return response.json();
}

export async function copyMarketingTemplateRequest(
	platformTemplateKey: string
): Promise<MarketingEmailTemplate> {
	const response = await fetch('/api/marketing/templates', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ platform_template_key: platformTemplateKey })
	});
	if (!response.ok) throw await readMarketingError(response, 'That template could not be copied.');
	const result = await response.json();
	return result.template;
}

export type CampaignLaunchResult = {
	campaign_id: string;
	status: string;
	revision: number;
	scheduled_for: string | null;
	launched_at: string;
	total_count: number;
	eligible_count: number;
	excluded_count: number;
	replayed: boolean;
};

export async function launchCampaignRequest(
	campaignId: string,
	revision: number,
	sendAt: string | null,
	idempotencyKey: string
): Promise<CampaignLaunchResult> {
	const response = await fetch(`/api/marketing/campaigns/${campaignId}/launch`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ revision, send_at: sendAt, idempotency_key: idempotencyKey })
	});
	if (!response.ok) {
		if (response.status === 409)
			throw new StaleCampaignError('Someone else changed this campaign.');
		throw await readMarketingError(response, 'That campaign could not be sent.');
	}
	return response.json();
}

export type CampaignCancelResult = {
	campaign_id: string;
	status: string;
	cancelled_at: string;
	cancelled_count: number;
	in_flight_count: number;
	submitted_count: number;
};

export async function cancelCampaignRequest(campaignId: string): Promise<CampaignCancelResult> {
	const response = await fetch(`/api/marketing/campaigns/${campaignId}/cancel`, { method: 'POST' });
	if (!response.ok)
		throw await readMarketingError(response, 'That campaign could not be cancelled.');
	return response.json();
}

export async function sendTestEmailRequest(
	content: MarketingCampaignContent,
	campaignId: string | null
): Promise<{ messageId: string }> {
	const response = await fetch('/api/marketing/campaigns/test-send', {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ content, campaign_id: campaignId })
	});
	if (!response.ok) throw await readMarketingError(response, 'That test email could not be sent.');
	return response.json();
}

// --- M5c: campaign detail tabs ----------------------------------------------------------------------------

export async function fetchCampaignOverview(
	campaignId: string
): Promise<MarketingCampaignOverview> {
	const response = await fetch(`/api/marketing/campaigns/${campaignId}/overview`);
	if (!response.ok)
		throw await readMarketingError(response, 'That campaign overview could not be loaded.');
	const result = await response.json();
	return result.overview;
}

export type CampaignRecipientsFilters = {
	statusFilter?: MarketingCampaignRecipientFilter | '';
	search?: string;
};

export async function fetchCampaignRecipients(
	campaignId: string,
	filters: CampaignRecipientsFilters,
	cursor?: string
): Promise<MarketingCampaignRecipientsPage> {
	const params = new URLSearchParams();
	if (filters.statusFilter) params.set('status', filters.statusFilter);
	if (filters.search) params.set('search', filters.search);
	if (cursor) params.set('cursor', cursor);
	const response = await fetch(
		`/api/marketing/campaigns/${campaignId}/recipients?${params.toString()}`
	);
	if (!response.ok) throw await readMarketingError(response, 'Recipients could not be loaded.');
	return response.json();
}

export async function fetchCampaignResults(campaignId: string): Promise<MarketingCampaignResults> {
	const response = await fetch(`/api/marketing/campaigns/${campaignId}/results`);
	if (!response.ok) throw await readMarketingError(response, 'Results could not be loaded.');
	const result = await response.json();
	return result.results;
}

export async function fetchCampaignAttributionCandidates(
	campaignId: string
): Promise<MarketingWindowAttributionCandidate[]> {
	const response = await fetch(`/api/marketing/campaigns/${campaignId}/attribution-candidates`);
	if (!response.ok)
		throw await readMarketingError(response, 'Possible matches could not be loaded.');
	const result = await response.json();
	return result.candidates;
}

export async function declareCampaignCreditRequest(
	campaignId: string,
	work: { requestId: string } | { jobId: string }
): Promise<void> {
	const response = await fetch(`/api/marketing/campaigns/${campaignId}/credits`, {
		method: 'POST',
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify(
			'requestId' in work ? { request_id: work.requestId } : { job_id: work.jobId }
		)
	});
	if (!response.ok) throw await readMarketingError(response, 'That work could not be credited.');
}

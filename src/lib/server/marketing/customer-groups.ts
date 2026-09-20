import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type {
	MarketingCustomerGroup,
	MarketingGroupRules,
	MarketingPreviewRecipient,
	MarketingRecipientPreviewCounts
} from '$lib/marketing/customer-groups';

// Saved customer groups and the recipient preview. The tables and functions are service-role only, so
// every function here takes the organization the API route already proved the caller belongs to, and
// nothing reads an organization id out of a request body.

export type SaveGroupInput = {
	name: string;
	description?: string;
	rules: MarketingGroupRules;
};

export class GroupNameTakenError extends Error {}
export class GroupChangedError extends Error {}

const GROUP_COLUMNS = 'id, name, description, rules, revision, updated_at';

// Postgres reports a broken unique index by code, so the API can turn it into a field message instead of
// a 500.
const UNIQUE_VIOLATION = '23505';

export async function listCustomerGroups(
	organizationId: string
): Promise<MarketingCustomerGroup[]> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner
		.from('marketing_customer_groups')
		.select(GROUP_COLUMNS)
		.eq('organization_id', organizationId)
		.is('archived_at', null)
		.order('normalized_name');
	if (error) throw error;
	return (data ?? []) as MarketingCustomerGroup[];
}

export async function createCustomerGroup(
	organizationId: string,
	userId: string,
	input: SaveGroupInput
): Promise<MarketingCustomerGroup> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner
		.from('marketing_customer_groups')
		.insert({
			organization_id: organizationId,
			name: input.name,
			description: input.description ?? null,
			rules: input.rules,
			created_by: userId,
			updated_by: userId
		})
		.select(GROUP_COLUMNS)
		.single();
	if (error) {
		if (error.code === UNIQUE_VIOLATION) throw new GroupNameTakenError();
		throw error;
	}
	return data as MarketingCustomerGroup;
}

// The caller sends the revision it last saw. A group someone else has changed in the meantime is refused
// rather than overwritten, and the page reloads the current version.
export async function updateCustomerGroup(
	organizationId: string,
	userId: string,
	groupId: string,
	revision: number,
	input: SaveGroupInput
): Promise<MarketingCustomerGroup> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner
		.from('marketing_customer_groups')
		.update({
			name: input.name,
			description: input.description ?? null,
			rules: input.rules,
			revision: revision + 1,
			updated_by: userId,
			updated_at: new Date().toISOString()
		})
		.eq('organization_id', organizationId)
		.eq('id', groupId)
		.eq('revision', revision)
		.is('archived_at', null)
		.select(GROUP_COLUMNS)
		.maybeSingle();
	if (error) {
		if (error.code === UNIQUE_VIOLATION) throw new GroupNameTakenError();
		throw error;
	}
	if (!data) throw new GroupChangedError();
	return data as MarketingCustomerGroup;
}

// Groups are archived, not deleted: a launched campaign records which group it came from, and that
// history has to keep making sense.
export async function archiveCustomerGroup(
	organizationId: string,
	groupId: string
): Promise<boolean> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner
		.from('marketing_customer_groups')
		.update({ archived_at: new Date().toISOString() })
		.eq('organization_id', organizationId)
		.eq('id', groupId)
		.is('archived_at', null)
		.select('id')
		.maybeSingle();
	if (error) throw error;
	return Boolean(data);
}

export async function previewCounts(
	organizationId: string,
	rules: MarketingGroupRules
): Promise<MarketingRecipientPreviewCounts> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner.rpc('marketing_preview_counts', {
		target_organization_id: organizationId,
		rules
	});
	if (error) throw error;
	return data as MarketingRecipientPreviewCounts;
}

export type RecipientPage = {
	status: 'all' | 'eligible' | 'excluded';
	after_display_name?: string;
	after_client_id?: string;
	page_size?: number;
};

export async function previewRecipients(
	organizationId: string,
	rules: MarketingGroupRules,
	page: RecipientPage
): Promise<MarketingPreviewRecipient[]> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner.rpc('marketing_preview_recipients', {
		target_organization_id: organizationId,
		rules,
		status_filter: page.status,
		after_display_name: page.after_display_name,
		after_client_id: page.after_client_id,
		page_size: page.page_size ?? 50
	});
	if (error) throw error;
	return (data ?? []) as MarketingPreviewRecipient[];
}

export type RuleLabel = { id: string; label: string };

// The rule builder only ever stores ids (a catalog item, a Customer). Reopening a saved group has to show
// their names again without a general-purpose "fetch by id list" on the Catalog or Client APIs, so this
// stays a small helper scoped to what the rule builder needs, reading the same tables `catalog.view` and
// `customers.view` already expose -- the caller has already proved `marketing.view` for the organization.
export async function hydrateRuleLabels(
	organizationId: string,
	catalogItemIds: string[],
	clientIds: string[]
): Promise<{ catalog_items: RuleLabel[]; clients: RuleLabel[] }> {
	const owner = getOwnerSupabaseClient();
	const [catalogResult, clientResult] = await Promise.all([
		catalogItemIds.length > 0
			? owner
					.from('catalog_items')
					.select('id, name')
					.eq('organization_id', organizationId)
					.in('id', catalogItemIds)
			: Promise.resolve({ data: [], error: null }),
		clientIds.length > 0
			? owner
					.from('clients')
					.select('id, display_name')
					.eq('organization_id', organizationId)
					.in('id', clientIds)
			: Promise.resolve({ data: [], error: null })
	]);
	if (catalogResult.error) throw catalogResult.error;
	if (clientResult.error) throw clientResult.error;
	return {
		catalog_items: (catalogResult.data ?? []).map((row) => ({ id: row.id, label: row.name })),
		clients: (clientResult.data ?? []).map((row) => ({ id: row.id, label: row.display_name }))
	};
}

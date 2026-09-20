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

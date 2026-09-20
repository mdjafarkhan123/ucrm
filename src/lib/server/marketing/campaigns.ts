import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type {
	MarketingCampaign,
	MarketingCampaignContent,
	MarketingCampaignListItem,
	MarketingGoal
} from '$lib/marketing/campaign-content';

// Campaign drafts. The table and its RPC are service-role only, so every function here takes the
// organization the API route already proved the caller belongs to, and nothing reads an organization id out
// of a request body -- same contract as src/lib/server/marketing/customer-groups.ts.

export class CampaignChangedError extends Error {}
export class CampaignInvalidError extends Error {}

const LIST_COLUMNS = 'id, name, goal, status, customer_group_id, updated_at';
const DETAIL_COLUMNS =
	'id, name, goal, status, customer_group_id, template_id, content, revision, updated_at';

export async function listCampaigns(organizationId: string): Promise<MarketingCampaignListItem[]> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner
		.from('marketing_campaigns')
		.select(LIST_COLUMNS)
		.eq('organization_id', organizationId)
		.order('updated_at', { ascending: false });
	if (error) throw error;
	return (data ?? []) as MarketingCampaignListItem[];
}

export async function getCampaign(
	organizationId: string,
	campaignId: string
): Promise<MarketingCampaign | null> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner
		.from('marketing_campaigns')
		.select(DETAIL_COLUMNS)
		.eq('organization_id', organizationId)
		.eq('id', campaignId)
		.maybeSingle();
	if (error) throw error;
	return data as MarketingCampaign | null;
}

export type CampaignDraftInput = {
	name: string;
	goal: MarketingGoal;
	customer_group_id?: string | null;
	template_id?: string | null;
	content: MarketingCampaignContent;
};

// Insert has no row to lock and re-check the way marketing_update_campaign_draft does for an edit, so a
// chosen group/template's organization ownership is proved here instead -- otherwise a client could hand a
// bare uuid belonging to another organization and the FK (which only points at the table, not this tenant)
// would happily accept it.
async function assertReferencesBelongToOrganization(
	owner: ReturnType<typeof getOwnerSupabaseClient>,
	organizationId: string,
	customerGroupId: string | null | undefined,
	templateId: string | null | undefined
): Promise<void> {
	if (customerGroupId) {
		const { data, error } = await owner
			.from('marketing_customer_groups')
			.select('id')
			.eq('id', customerGroupId)
			.eq('organization_id', organizationId)
			.is('archived_at', null)
			.maybeSingle();
		if (error) throw error;
		if (!data) throw new CampaignInvalidError('Choose a saved customer group.');
	}
	if (templateId) {
		const { data, error } = await owner
			.from('marketing_email_templates')
			.select('id')
			.eq('id', templateId)
			.eq('organization_id', organizationId)
			.maybeSingle();
		if (error) throw error;
		if (!data) throw new CampaignInvalidError('Choose a valid template.');
	}
}

export async function createCampaign(
	organizationId: string,
	userId: string,
	input: CampaignDraftInput
): Promise<MarketingCampaign> {
	const owner = getOwnerSupabaseClient();
	await assertReferencesBelongToOrganization(
		owner,
		organizationId,
		input.customer_group_id,
		input.template_id
	);
	const { data, error } = await owner
		.from('marketing_campaigns')
		.insert({
			organization_id: organizationId,
			name: input.name,
			goal: input.goal,
			customer_group_id: input.customer_group_id ?? null,
			template_id: input.template_id ?? null,
			content: input.content,
			created_by: userId,
			updated_by: userId
		})
		.select(DETAIL_COLUMNS)
		.single();
	if (error) throw error;
	return data as MarketingCampaign;
}

// The caller sends the revision it last saw. A campaign someone else has changed in the meantime is
// refused rather than overwritten, and the page reloads the current version. Unlike Customer Groups' plain
// filtered update, this goes through marketing_update_campaign_draft: it also re-checks the campaign is
// still a draft and that the chosen customer group/template still belong to this organization, inside the
// same row lock, which a PostgREST-level `.eq('revision', revision)` update cannot do.
export async function updateCampaignDraft(
	organizationId: string,
	userId: string,
	campaignId: string,
	revision: number,
	input: CampaignDraftInput
): Promise<{ revision: number; updated_at: string }> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner.rpc('marketing_update_campaign_draft', {
		target_organization_id: organizationId,
		target_campaign_id: campaignId,
		actor_user_id: userId,
		expected_revision: revision,
		new_name: input.name,
		new_goal: input.goal,
		// The generated RPC arg types say `string`, not `string | null`, because Postgres codegen does not
		// mark a nullable uuid parameter as nullable -- the function itself accepts and expects null here.
		new_customer_group_id: (input.customer_group_id ?? null) as string,
		new_template_id: (input.template_id ?? null) as string,
		new_content: input.content
	});
	if (error) {
		if (error.code === 'P0409') throw new CampaignChangedError(error.message);
		if (error.code === '23514') throw new CampaignInvalidError(error.message);
		throw error;
	}
	return data as { revision: number; updated_at: string };
}

// A draft that was never sent is simply removed, unlike a customer group: it has no launch history to
// preserve. Anything past 'draft' status is M4's territory and this never touches it.
export async function deleteCampaignDraft(
	organizationId: string,
	campaignId: string
): Promise<boolean> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner
		.from('marketing_campaigns')
		.delete()
		.eq('organization_id', organizationId)
		.eq('id', campaignId)
		.eq('status', 'draft')
		.select('id')
		.maybeSingle();
	if (error) throw error;
	return Boolean(data);
}

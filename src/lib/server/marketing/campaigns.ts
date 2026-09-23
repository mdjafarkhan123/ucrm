import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import type {
	MarketingCampaign,
	MarketingCampaignContent,
	MarketingCampaignListItem,
	MarketingCampaignOverview,
	MarketingCampaignRecipient,
	MarketingCampaignRecipientsPage,
	MarketingCampaignResults,
	MarketingGoal,
	MarketingWindowAttributionCandidate
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

export class CampaignNotCancellableError extends Error {}

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

// Confirming a campaign. Everything that makes it irreversible happens inside marketing_launch_campaign, in
// one transaction: the audience is frozen into marketing_campaign_recipients, the Marketing allowance is
// reserved, and the campaign leaves draft. This wrapper only carries the call and turns the two refusals the
// caller can act on into the same errors updateCampaignDraft raises.
//
// `idempotencyKey` is what makes a retried request safe: the same key answers with the original launch
// instead of sending to the same people twice. The caller must reuse one key per user action, not per attempt.
// The marketing.launch permission and the readiness checks belong to the route, as with every other command
// here -- the RPC is service-role only and trusts the organization it is given.
export async function launchCampaign(
	organizationId: string,
	userId: string,
	campaignId: string,
	revision: number,
	sendAt: string | null,
	idempotencyKey: string
): Promise<CampaignLaunchResult> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner.rpc('marketing_launch_campaign', {
		target_organization_id: organizationId,
		target_campaign_id: campaignId,
		actor_user_id: userId,
		expected_revision: revision,
		// Postgres codegen does not mark a nullable timestamptz parameter as nullable; null is what the
		// function expects for "send it now".
		send_at: sendAt as string,
		idempotency_key: idempotencyKey
	});
	if (error) {
		if (error.code === 'P0409') throw new CampaignChangedError(error.message);
		if (error.code === '23514') throw new CampaignInvalidError(error.message);
		throw error;
	}
	return data as unknown as CampaignLaunchResult;
}

export type CampaignCancelResult = {
	campaign_id: string;
	status: string;
	cancelled_at: string;
	cancelled_count: number;
	in_flight_count: number;
	submitted_count: number;
};

// Cancelling a scheduled or sending campaign. Idempotent by design (marketing_cancel_campaign reports zero
// newly-cancelled recipients rather than erroring on a second call), so this never needs an idempotency key
// the way launch does. The marketing.launch permission belongs to the calling route, as with every other
// marketing command.
export async function cancelCampaign(
	organizationId: string,
	userId: string,
	campaignId: string
): Promise<CampaignCancelResult> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner.rpc('marketing_cancel_campaign', {
		target_organization_id: organizationId,
		target_campaign_id: campaignId,
		actor_user_id: userId
	});
	if (error) {
		if (error.code === '23514') throw new CampaignNotCancellableError(error.message);
		throw error;
	}
	return data as unknown as CampaignCancelResult;
}

// M5b attribution: authorized staff connecting a resulting Request/Job to a campaign after reviewing the
// Customer and timing (blueprint §13 method 2). marketing.draft is the calling route's job to enforce, as
// with every other marketing command.

export class CampaignCreditInvalidError extends Error {}
export class CampaignCreditConflictError extends Error {}

export type CampaignResultCredit = {
	id: string;
	organization_id: string;
	campaign_id: string;
	marketing_campaign_recipient_id: string | null;
	source: 'tracked' | 'declared';
	request_id: string | null;
	job_id: string | null;
	client_id: string;
	credited_at: string;
	declared_by: string | null;
};

export async function declareCampaignCredit(
	organizationId: string,
	userId: string,
	campaignId: string,
	work: { requestId: string; jobId?: undefined } | { jobId: string; requestId?: undefined }
): Promise<CampaignResultCredit> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner.rpc('declare_marketing_campaign_result_credit', {
		target_organization_id: organizationId,
		target_campaign_id: campaignId,
		actor_user_id: userId,
		...(work.requestId ? { target_request_id: work.requestId } : { target_job_id: work.jobId })
	});
	if (error) {
		if (error.code === '23505') throw new CampaignCreditConflictError(error.message);
		if (error.code === '23514') throw new CampaignCreditInvalidError(error.message);
		throw error;
	}
	return data as unknown as CampaignResultCredit;
}

// ---------------------------------------------------------------------------------------------------
// M5c: the campaign detail page's Overview, Recipients, and Results tabs (blueprint §12-13).
// ---------------------------------------------------------------------------------------------------

// One literal line, not built by concatenation -- supabase-js only infers a select's column shape from a
// literal string, and a `+`-joined one widens to plain `string` and loses it (unlike LIST_COLUMNS/DETAIL_COLUMNS
// above, which are already single literals).
const OVERVIEW_COLUMNS =
	'id, name, goal, status, customer_group_id, template_id, content, revision, created_at, updated_at, scheduled_for, launched_at, launched_by, recipient_total_count, recipient_eligible_count, recipient_excluded_count';

type RecipientCountsRow = {
	waiting_count: number;
	submitted_count: number;
	delivered_count: number;
	failed_count: number;
	excluded_count: number;
	cancelled_count: number;
	bounced_count: number;
	complained_count: number;
	unsubscribed_count: number;
	opened_count: number;
	clicked_count: number;
};

const EMPTY_RECIPIENT_COUNTS: RecipientCountsRow = {
	waiting_count: 0,
	submitted_count: 0,
	delivered_count: 0,
	failed_count: 0,
	excluded_count: 0,
	cancelled_count: 0,
	bounced_count: 0,
	complained_count: 0,
	unsubscribed_count: 0,
	opened_count: 0,
	clicked_count: 0
};

// The Overview tab: campaign summary, its customer group's name (the campaign only stores the id), and the
// five recipient buckets (blueprint §12) from marketing_campaign_recipient_counts -- one indexed scan of
// this campaign's own rows, never the organization's full recipient history.
export async function getCampaignOverview(
	organizationId: string,
	campaignId: string
): Promise<MarketingCampaignOverview | null> {
	const owner = getOwnerSupabaseClient();
	const { data: campaign, error } = await owner
		.from('marketing_campaigns')
		.select(OVERVIEW_COLUMNS)
		.eq('organization_id', organizationId)
		.eq('id', campaignId)
		.maybeSingle();
	if (error) throw error;
	if (!campaign) return null;

	const [{ data: group, error: groupError }, { data: counts, error: countsError }] =
		await Promise.all([
			campaign.customer_group_id
				? owner
						.from('marketing_customer_groups')
						.select('name')
						.eq('id', campaign.customer_group_id)
						.maybeSingle()
				: Promise.resolve({ data: null, error: null }),
			owner.rpc('marketing_campaign_recipient_counts', {
				target_organization_id: organizationId,
				target_campaign_id: campaignId
			})
		]);
	if (groupError) throw groupError;
	if (countsError) throw countsError;

	const row = ((counts as RecipientCountsRow[] | null)?.[0] ??
		EMPTY_RECIPIENT_COUNTS) as RecipientCountsRow;

	return {
		...(campaign as unknown as Omit<MarketingCampaignOverview, 'customer_group_name' | 'counts'>),
		customer_group_name: (group as { name: string } | null)?.name ?? null,
		counts: {
			waiting: row.waiting_count,
			submitted: row.submitted_count,
			delivered: row.delivered_count,
			failed_excluded: row.failed_count + row.excluded_count,
			cancelled: row.cancelled_count
		}
	};
}

const RECIPIENT_PAGE_SIZE = 50;

// A recipient page, keyset-paginated on the (campaign_id, status, display_name, id) index this campaign's
// recipients already carry -- the cursor is "<display_name>|<id>" the same shape src/routes/api/invoices'
// own cursor uses, so a tied name never skips or repeats a row.
type RecipientRow = Omit<MarketingCampaignRecipient, 'credit'>;

export async function listCampaignRecipients(
	organizationId: string,
	campaignId: string,
	options: { cursor?: string; statusFilter?: string; search?: string } = {}
): Promise<MarketingCampaignRecipientsPage> {
	const owner = getOwnerSupabaseClient();
	let query = owner
		.from('marketing_campaign_recipients')
		.select(
			'id, client_id, display_name, recipient_email, status, excluded_reason, delivered_at, first_opened_at, first_clicked_at, unsubscribed_at'
		)
		.eq('organization_id', organizationId)
		.eq('campaign_id', campaignId)
		.order('display_name', { ascending: true })
		.order('id', { ascending: true })
		.limit(RECIPIENT_PAGE_SIZE + 1);

	// Matches the same buckets marketing_campaign_recipient_counts groups by, so a filtered list and the
	// Overview tab's counts never disagree about what "Delivered" or "Failed" means.
	if (options.statusFilter === 'engaged') {
		query = query.not('first_opened_at', 'is', null);
	} else if (options.statusFilter === 'delivered') {
		query = query.not('delivered_at', 'is', null);
	} else if (options.statusFilter === 'unsubscribed') {
		query = query.not('unsubscribed_at', 'is', null);
	} else if (options.statusFilter === 'failed') {
		query = query.in('status', ['bounced', 'complained', 'failed']);
	} else if (options.statusFilter) {
		query = query.eq('status', options.statusFilter);
	}
	if (options.search) {
		const like = options.search.replace(/[%_]/g, (match) => `\\${match}`);
		query = query.or(`display_name.ilike.%${like}%,recipient_email.ilike.%${like}%`);
	}
	if (options.cursor) {
		const separator = options.cursor.lastIndexOf('|');
		if (separator > 0) {
			const name = options.cursor.slice(0, separator);
			const id = options.cursor.slice(separator + 1);
			// display_name strictly after the cursor's name, or tied on name and after its id -- a composite
			// keyset predicate PostgREST expresses through .or() rather than a tuple comparison.
			const escapedName = name.replace(/[,()]/g, (match) => `\\${match}`);
			query = query.or(
				`display_name.gt.${escapedName},and(display_name.eq.${escapedName},id.gt.${id})`
			);
		}
	}

	const { data, error } = await query;
	if (error) throw error;
	const rows = (data ?? []) as unknown as RecipientRow[];
	const page = rows.slice(0, RECIPIENT_PAGE_SIZE);
	const hasMore = rows.length > RECIPIENT_PAGE_SIZE;

	// Attribution per recipient: a tracked credit carries this recipient's own id; a declared credit only
	// carries the client, so both are matched by client_id -- the join a single small query does once per
	// page rather than once per row.
	const clientIds = [...new Set(page.map((row) => row.client_id))];
	const { data: credits, error: creditsError } = clientIds.length
		? await owner
				.from('marketing_campaign_result_credits')
				.select('client_id, source, request_id, job_id')
				.eq('organization_id', organizationId)
				.eq('campaign_id', campaignId)
				.in('client_id', clientIds)
		: { data: [], error: null };
	if (creditsError) throw creditsError;
	const creditByClient = new Map(
		(credits ?? []).map((credit) => [
			credit.client_id,
			{
				source: credit.source as 'tracked' | 'declared',
				request_id: credit.request_id,
				job_id: credit.job_id
			}
		])
	);

	const last = page.at(-1);
	return {
		recipients: page.map((row) => ({
			...row,
			credit: creditByClient.get(row.client_id) ?? null
		})),
		next_cursor: hasMore && last ? `${last.display_name}|${last.id}` : null
	};
}

// The Results tab: delivery breakdown, credited Requests/Jobs with real revenue, and the launch-frozen
// matched/eligible counts (blueprint §12 Q1-3). "Submitted" = every recipient past waiting/checking, whether
// it went on to deliver, fail, or get cancelled.
export async function getCampaignResults(
	organizationId: string,
	campaignId: string
): Promise<MarketingCampaignResults | null> {
	const owner = getOwnerSupabaseClient();
	const { data: campaign, error: campaignError } = await owner
		.from('marketing_campaigns')
		.select('recipient_total_count, recipient_eligible_count, recipient_excluded_count')
		.eq('organization_id', organizationId)
		.eq('id', campaignId)
		.maybeSingle();
	if (campaignError) throw campaignError;
	if (!campaign) return null;

	const [
		{ data: counts, error: countsError },
		{ data: credited, error: creditedError },
		{ data: settings, error: settingsError }
	] = await Promise.all([
		owner.rpc('marketing_campaign_recipient_counts', {
			target_organization_id: organizationId,
			target_campaign_id: campaignId
		}),
		owner.rpc('marketing_campaign_credited_work', {
			target_organization_id: organizationId,
			target_campaign_id: campaignId
		}),
		// Revenue is shown in the organization's own currency -- the single source of truth every invoice
		// already prices in, the same lookup process_next_form_submission uses.
		owner
			.from('organization_settings')
			.select('currency_code')
			.eq('organization_id', organizationId)
			.maybeSingle()
	]);
	if (countsError) throw countsError;
	if (creditedError) throw creditedError;
	if (settingsError) throw settingsError;

	const row = ((counts as RecipientCountsRow[] | null)?.[0] ??
		EMPTY_RECIPIENT_COUNTS) as RecipientCountsRow;
	const work = (credited ?? []) as MarketingCampaignResults['credited_work'];
	const submitted =
		row.submitted_count + row.delivered_count + row.failed_count + row.cancelled_count;

	return {
		matched_count: campaign.recipient_total_count ?? 0,
		eligible_count: campaign.recipient_eligible_count ?? 0,
		excluded_count: campaign.recipient_excluded_count ?? 0,
		submitted_count: submitted,
		delivered_count: row.delivered_count,
		bounced_count: row.bounced_count,
		complained_count: row.complained_count,
		unsubscribed_count: row.unsubscribed_count,
		opened_count: row.opened_count,
		clicked_count: row.clicked_count,
		credited_work: work,
		revenue_minor: work.reduce((sum, item) => sum + item.revenue_minor, 0),
		currency_code: (settings as { currency_code: string } | null)?.currency_code ?? 'USD'
	};
}

// The Results tab's "possible matches" browser: uncredited work this campaign's own last-touch window
// (blueprint §13 method 3) would currently win, for staff to review and, if it really is this campaign's
// result, declare through the existing declareCampaignCredit command.
export async function listWindowAttributionCandidates(
	organizationId: string,
	campaignId: string,
	windowDays = 30
): Promise<MarketingWindowAttributionCandidate[]> {
	const owner = getOwnerSupabaseClient();
	const { data, error } = await owner.rpc('marketing_campaign_window_attribution_candidates', {
		target_organization_id: organizationId,
		target_campaign_id: campaignId,
		window_days: windowDays
	});
	if (error) throw error;
	return (data ?? []) as MarketingWindowAttributionCandidate[];
}

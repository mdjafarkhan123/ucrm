import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import {
	PRIVATE_READ_HEADERS,
	databaseError,
	notFound,
	validationError
} from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { presentHistory, type RawHistoryPage } from '$lib/server/jafar/lead-history';
import { leadChangeSchema } from '$lib/server/validation/lead.schema';
import type { LeadPage } from '$lib/jafar/lead-history';
import { canUseJafarPath } from '$lib/jafar/team-access';
import type { BusinessClient, BusinessDeal } from '$lib/jafar/deals';
import type { Json } from '$lib/database.types';
import { readSetupCatalogue } from '$lib/server/setup/catalogue';
import { presentOnboardingRows, type RawOnboardingClient } from '$lib/server/setup/onboarding-list';
import { onboardingCatalogue } from '$lib/setup/onboarding-list';

// Jafar business management B2: one Lead's page in one request, and changing its status or next action. Each
// change is written to the Lead's history in the same database transaction.

const LEAD_NOT_FOUND = 'This Lead no longer exists.';

/**
 * B5: the Client box with its onboarding row, read only once the account exists and only for someone who can
 * open Onboarding. Payments and the package are Application details, shown only to someone who can open those.
 */
async function presentClient(
	client: ReturnType<typeof getOwnerSupabaseClient>,
	won: Omit<BusinessClient, 'onboarding'> | null,
	sees: { applications: boolean; onboarding: boolean }
): Promise<BusinessClient | null> {
	if (!won) return null;
	const organizationId = won.account?.organization_id ?? null;
	let onboarding: BusinessClient['onboarding'] = null;
	if (organizationId && sees.onboarding) {
		const catalogue = await readSetupCatalogue(client);
		if (catalogue) {
			const { data, error } = await client.rpc('owner_client_onboarding_list', {
				setup_catalogue: onboardingCatalogue(catalogue) as Json,
				include_delivered: true,
				only_organization_id: organizationId,
				page_size: 1
			});
			if (error) throw error;
			const rows = (data as { clients: RawOnboardingClient[] } | null)?.clients ?? [];
			onboarding = (await presentOnboardingRows(client, catalogue, rows))?.[0] ?? null;
		}
	}
	return {
		...won,
		application: sees.applications ? won.application : null,
		payments: sees.applications ? won.payments : [],
		onboarding
	};
}

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);

	try {
		// B4: the business's Deals are read alongside, in the same request.
		// B5: and its Client box, once a Deal is Won.
		const client = getOwnerSupabaseClient();
		const [{ data, error }, deals, won] = await Promise.all([
			client.rpc('owner_lead_page', { target_id: event.params.id }),
			client.rpc('owner_business_deals', { target_relationship_id: event.params.id }),
			client.rpc('owner_business_client', { target_relationship_id: event.params.id })
		]);
		if (error) throw error;
		if (deals.error) throw deals.error;
		if (won.error) throw won.error;
		if (!data) return notFound(LEAD_NOT_FOUND);

		const page = data as unknown as Omit<LeadPage, 'history' | 'deals' | 'client'> & {
			history: RawHistoryPage;
		};
		// Linked Applications carry their contact's details: only for someone who can open Applications.
		const seesApplications = canUseJafarPath(session, '/api/jafar/prospects');
		const applications = seesApplications ? page.applications : [];
		return json(
			{
				...page,
				applications,
				deals: deals.data as unknown as BusinessDeal[],
				client: await presentClient(
					client,
					won.data as unknown as Omit<BusinessClient, 'onboarding'> | null,
					{
						applications: seesApplications,
						onboarding: canUseJafarPath(session, '/api/jafar/onboarding')
					}
				),
				history: presentHistory(page.history)
			} satisfies LeadPage,
			{
				headers: PRIVATE_READ_HEADERS
			}
		);
	} catch (error) {
		console.error('Could not load the Lead.', error);
		return json({ error: 'This Lead could not be loaded.' }, { status: 500 });
	}
};

export const PATCH: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	if (!z.uuid().safeParse(event.params.id).success) return notFound(LEAD_NOT_FOUND);

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}
	const parsed = leadChangeSchema.safeParse(body);
	if (!parsed.success) {
		const fieldErrors: Record<string, string> = {};
		for (const issue of parsed.error.issues)
			fieldErrors[issue.path.join('.') || 'form'] ??= issue.message;
		return validationError(fieldErrors);
	}

	const change = parsed.data;
	const next = change.next_action;
	try {
		const { data, error } = await getOwnerSupabaseClient().rpc('owner_lead_change', {
			actor_email: session.email,
			target_id: event.params.id,
			target_status: change.lead_status,
			next_action_mode: next?.mode ?? 'keep',
			target_next_action: next && next.mode !== 'clear' ? (next.text ?? undefined) : undefined,
			target_due_on: next && next.mode !== 'clear' ? (next.due_on ?? undefined) : undefined
		});
		if (error) {
			// The database's own refusals (e.g. "There is no next action to mark done.") are already in plain words.
			if (error.code === '22023') return validationError({ form: error.message }, 409);
			throw error;
		}
		if (!data) return notFound(LEAD_NOT_FOUND);
		return json({ ok: true });
	} catch (error) {
		console.error('Could not change the Lead.', error);
		return databaseError();
	}
};

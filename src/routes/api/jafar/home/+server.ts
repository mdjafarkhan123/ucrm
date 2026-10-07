import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import type { Json } from '$lib/database.types';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readSetupCatalogue } from '$lib/server/setup/catalogue';
import { onboardingCatalogue } from '$lib/setup/onboarding-list';
import { HOME_AGENDA_LIMIT, type BusinessHome } from '$lib/jafar/business-home';

// Jafar business management C1: the Business Management home in one request. The Leads and Applications counts
// and the to-do list come from one database call; the clients waiting on Uplift and the renewals to chase reuse
// the onboarding list's and the organization directory's own counts, so each number matches the page it opens.
// Those two run alongside; if one fails its tile shows a dash and the rest of the day still loads.
// No area claims this route, so the front-door gate keeps it to Jafar until teammates get a home (D3).

const todaySchema = z.iso.date();

type HomeCore = Omit<BusinessHome, 'setups_waiting' | 'renewals'>;

async function setupsWaitingOnUplift(client: ReturnType<typeof getOwnerSupabaseClient>) {
	const catalogue = await readSetupCatalogue(client);
	if (!catalogue) throw new Error('The setup catalogue could not be read.');
	const { data, error } = await client.rpc('owner_client_onboarding_list', {
		setup_catalogue: onboardingCatalogue(catalogue) as Json,
		waiting_filter: 'uplift',
		page_size: 1
	});
	if (error) throw error;
	return (data as { totals: { uplift: number } }).totals.uplift;
}

async function renewalsToChase(client: ReturnType<typeof getOwnerSupabaseClient>) {
	const { data, error } = await client.rpc('owner_organization_directory', { page_size: 1 });
	if (error) throw error;
	const attention = (data as { totals: { attention: Record<string, number> } }).totals.attention;
	return (attention.renewal_due ?? 0) + (attention.payment_overdue ?? 0);
}

export const GET: RequestHandler = async (event) => {
	if (!(await getOwnerSession(event))) return ownerUnauthorized();
	const today = todaySchema.safeParse(event.url.searchParams.get('today'));
	if (!today.success) return json({ error: 'The date is invalid.' }, { status: 422 });

	const client = getOwnerSupabaseClient();
	const [core, setups, renewals] = await Promise.allSettled([
		client.rpc('owner_business_home', { today_date: today.data, agenda_limit: HOME_AGENDA_LIMIT }),
		setupsWaitingOnUplift(client),
		renewalsToChase(client)
	]);

	if (core.status === 'rejected' || core.value.error) {
		console.error(
			'Could not load the Business Management home.',
			core.status === 'rejected' ? core.reason : core.value.error
		);
		return json({ error: 'Your day could not be loaded.' }, { status: 500 });
	}
	if (setups.status === 'rejected')
		console.error('Could not count clients waiting on Uplift.', setups.reason);
	if (renewals.status === 'rejected') console.error('Could not count renewals.', renewals.reason);

	const home: BusinessHome = {
		...(core.value.data as unknown as HomeCore),
		setups_waiting: setups.status === 'fulfilled' ? setups.value : null,
		renewals: renewals.status === 'fulfilled' ? renewals.value : null
	};
	return json(home, { headers: PRIVATE_READ_HEADERS });
};

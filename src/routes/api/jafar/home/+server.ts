import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import type { Json } from '$lib/database.types';
import { PRIVATE_READ_HEADERS } from '$lib/server/api/errors';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { readSetupCataloguesInUse } from '$lib/server/setup/catalogue';
import { onboardingCatalogues } from '$lib/setup/onboarding-list';
import { HOME_AGENDA_LIMIT, homeCountsOpen, type BusinessHome } from '$lib/jafar/business-home';

// Jafar business management C1: the Business Management home in one request. The Leads and Applications counts
// and the to-do list come from one database call; the clients waiting on Uplift and the renewals to chase reuse
// the onboarding list's and the organization directory's own counts, so each number matches the page it opens.
// Those two run alongside; if one fails its tile shows a dash and the rest of the day still loads.
// D3b: everyone signed in has a home. The to-do list and first contacts are the viewer's own; Jafar can ask for the
// whole team's (`everyone=1`). A count whose list the viewer cannot open is left out (null) and never worked out.

const todaySchema = z.iso.date();

type HomeCore = Omit<BusinessHome, 'setups_waiting' | 'renewals'>;

async function setupsWaitingOnUplift(client: ReturnType<typeof getOwnerSupabaseClient>) {
	const catalogue = await readSetupCataloguesInUse(client);
	if (!catalogue) throw new Error('The setup versions could not be read.');
	const { data, error } = await client.rpc('owner_client_onboarding_list', {
		setup_catalogue: onboardingCatalogues(catalogue) as Json,
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
	const session = await getOwnerSession(event);
	if (!session) return ownerUnauthorized();
	const today = todaySchema.safeParse(event.url.searchParams.get('today'));
	if (!today.success) return json({ error: 'The date is invalid.' }, { status: 422 });
	// Only Jafar sees the whole team's to-dos.
	const everyone = session.role === null && event.url.searchParams.get('everyone') === '1';
	const open = homeCountsOpen(session);

	const client = getOwnerSupabaseClient();
	const [core, setups, renewals] = await Promise.allSettled([
		client.rpc('owner_business_home', {
			today_date: today.data,
			agenda_limit: HOME_AGENDA_LIMIT,
			viewer_member_id: session.memberId ?? undefined,
			everyone
		}),
		open.setups_waiting ? setupsWaitingOnUplift(client) : Promise.resolve(null),
		open.renewals ? renewalsToChase(client) : Promise.resolve(null)
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

	const counts = core.value.data as unknown as HomeCore;
	const home: BusinessHome = {
		...counts,
		review: open.review ? counts.review : null,
		first_contact: open.first_contact ? counts.first_contact : null,
		accounts_to_create: open.accounts_to_create ? counts.accounts_to_create : null,
		setups_waiting: setups.status === 'fulfilled' ? setups.value : null,
		renewals: renewals.status === 'fulfilled' ? renewals.value : null
	};
	return json(home, { headers: PRIVATE_READ_HEADERS });
};

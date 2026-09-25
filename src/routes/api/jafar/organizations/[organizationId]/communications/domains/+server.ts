import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

const noStore = { 'Cache-Control': 'no-store' };

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) {
		const response = ownerUnauthorized();
		response.headers.set('Cache-Control', 'no-store');
		return response;
	}

	const organizationId = organizationIdSchema.safeParse(event.params.organizationId);
	if (!organizationId.success) {
		return json(
			{ error: 'The organization identifier is invalid.' },
			{ status: 422, headers: noStore }
		);
	}

	const client = getOwnerSupabaseClient();
	const { data, error } = await client
		.from('communication_email_domains')
		.select(
			'id, purpose, provider, domain_name, dns_zone, lifecycle_state, ownership_status, dkim_status, dmarc_status, spf_status, inbound_mx_status, provider_verified, provider_authenticated, last_checked_at, verified_at, warmup_started_at, transition_until, replacement_of_domain_id, provider_cleanup_error, created_at'
		)
		.eq('organization_id', organizationId.data)
		.in('purpose', ['sending', 'receiving'])
		.neq('lifecycle_state', 'removed')
		// Newest first: the Email card shows one row per purpose, so if an older row were ever still live it
		// must pick the newest.
		.order('created_at', { ascending: false });

	if (error) {
		console.error('Could not load sending domains for the owner.', error);
		return json({ error: 'Email domains could not be loaded.' }, { status: 500, headers: noStore });
	}

	return json({ domains: data ?? [] }, { headers: noStore });
};

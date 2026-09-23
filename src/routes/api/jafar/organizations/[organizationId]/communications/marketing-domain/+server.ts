import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

const noStore = { 'Cache-Control': 'no-store' };

// Lists this organization's Marketing sending domain(s) for the owner panel. Read-only counterpart to the
// activate/recheck routes; at most one live row exists per organization today (no replace/remove yet).
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
	const [{ data, error }, { data: rootRow, error: rootError }] = await Promise.all([
		client
			.from('communication_email_domains')
			.select(
				'id, domain_name, dns_zone, lifecycle_state, ownership_status, dkim_status, spf_status, provider_verified, provider_authenticated, last_checked_at, verified_at, created_at'
			)
			.eq('organization_id', organizationId.data)
			.eq('purpose', 'marketing_sending')
			.neq('lifecycle_state', 'removed')
			.order('created_at'),
		// The organization's existing receiving domain's root is a reliable prefill suggestion for the
		// Marketing activation form, since it is unique per organization and already verified.
		client
			.from('communication_email_domains')
			.select('dns_zone')
			.eq('organization_id', organizationId.data)
			.eq('purpose', 'receiving')
			.neq('lifecycle_state', 'removed')
			.maybeSingle()
	]);

	if (error) {
		console.error('Could not load Marketing domains for the owner.', error);
		return json(
			{ error: 'Marketing domains could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}
	if (rootError) {
		console.error('Could not load the suggested root domain for Marketing.', rootError);
	}

	return json(
		{ domains: data ?? [], suggested_root_domain: rootRow?.dns_zone ?? null },
		{ headers: noStore }
	);
};

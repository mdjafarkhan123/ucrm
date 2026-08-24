import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { ownerUnauthorized } from '$lib/server/access/owner';
import { getOwnerSession } from '$lib/server/auth/owner';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import { z } from 'zod';

const noStore = { 'Cache-Control': 'no-store' };
const domainIdSchema = z.string().uuid();

type StoredDnsRecord = {
	type?: unknown;
	host_name?: unknown;
	value?: unknown;
	status?: unknown;
};

function safeRecords(value: unknown) {
	if (!Array.isArray(value)) return [];
	return value.flatMap((record: StoredDnsRecord) => {
		if (
			typeof record?.type !== 'string' ||
			typeof record.host_name !== 'string' ||
			typeof record.value !== 'string'
		)
			return [];
		return [
			{
				type: record.type,
				host_name: record.host_name,
				value: record.value,
				status: record.status === true
			}
		];
	});
}

export const GET: RequestHandler = async (event) => {
	const session = await getOwnerSession(event);
	if (!session) {
		const response = ownerUnauthorized();
		response.headers.set('Cache-Control', 'no-store');
		return response;
	}

	const organizationId = organizationIdSchema.safeParse(event.params.organizationId);
	const domainId = domainIdSchema.safeParse(event.params.domainId);
	if (!organizationId.success || !domainId.success) {
		return json({ error: 'The domain identifier is invalid.' }, { status: 422, headers: noStore });
	}

	const { data: domain, error } = await getOwnerSupabaseClient()
		.from('communication_email_domains')
		.select('domain_name, dns_zone, dns_records, last_checked_at')
		.eq('organization_id', organizationId.data)
		.eq('id', domainId.data)
		.eq('purpose', 'sending')
		.neq('lifecycle_state', 'removed')
		.maybeSingle();

	if (error) {
		console.error('Could not load sending-domain DNS setup for the owner.', error);
		return json(
			{ error: 'DNS setup records could not be loaded.' },
			{ status: 500, headers: noStore }
		);
	}
	if (!domain)
		return json({ error: 'Sending domain was not found.' }, { status: 404, headers: noStore });

	return json(
		{
			domain_name: domain.domain_name,
			dns_zone: domain.dns_zone,
			last_checked_at: domain.last_checked_at,
			dns_records: safeRecords(domain.dns_records)
		},
		{ headers: noStore }
	);
};

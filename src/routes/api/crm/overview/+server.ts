import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { databaseError } from '$lib/server/api/errors';

export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth)
		return new Response(
			JSON.stringify({ error: 'Authentication or organization membership required' }),
			{ status: 401, headers: { 'content-type': 'application/json' } }
		);

	const { organization } = auth;
	const [clients, contactMethods, properties, requests] = await Promise.all([
		event.locals.supabase
			.from('clients')
			.select('*')
			.eq('organization_id', organization.id)
			.is('deleted_at', null)
			.order('updated_at', { ascending: false }),
		event.locals.supabase
			.from('client_contact_methods')
			.select('client_id, kind, value')
			.eq('organization_id', organization.id)
			.eq('is_primary', true),
		event.locals.supabase
			.from('properties')
			.select('*')
			.eq('organization_id', organization.id)
			.is('deleted_at', null)
			.order('updated_at', { ascending: false }),
		event.locals.supabase
			.from('requests')
			.select('*')
			.eq('organization_id', organization.id)
			.order('updated_at', { ascending: false })
	]);

	if (clients.error || contactMethods.error || properties.error || requests.error)
		return databaseError();

	// Email and phone live in client_contact_methods, so the primary values are folded back in here.
	const primaryByClient = new Map<string, { email: string | null; phone: string | null }>();
	for (const method of contactMethods.data ?? []) {
		const entry = primaryByClient.get(method.client_id) ?? { email: null, phone: null };
		if (method.kind === 'email') entry.email = method.value;
		else entry.phone = method.value;
		primaryByClient.set(method.client_id, entry);
	}

	return json({
		organization,
		clients: (clients.data ?? []).map((client) => ({
			...client,
			email: primaryByClient.get(client.id)?.email ?? null,
			phone: primaryByClient.get(client.id)?.phone ?? null
		})),
		properties: properties.data ?? [],
		requests: requests.data ?? []
	});
};

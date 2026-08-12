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
	const [contacts, properties, requests] = await Promise.all([
		event.locals.supabase
			.from('contacts')
			.select('*')
			.eq('organization_id', organization.id)
			.order('updated_at', { ascending: false }),
		event.locals.supabase
			.from('properties')
			.select('*')
			.eq('organization_id', organization.id)
			.order('updated_at', { ascending: false }),
		event.locals.supabase
			.from('requests')
			.select('*')
			.eq('organization_id', organization.id)
			.order('updated_at', { ascending: false })
	]);

	if (contacts.error || properties.error || requests.error) return databaseError();

	return json({
		organization,
		contacts: contacts.data ?? [],
		properties: properties.data ?? [],
		requests: requests.data ?? []
	});
};

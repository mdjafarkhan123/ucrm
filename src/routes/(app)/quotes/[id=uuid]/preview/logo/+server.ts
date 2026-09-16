import { error as httpError } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireContractor } from '$lib/server/auth/guards';
import { streamOrganizationLogo } from '$lib/server/settings/logo';

// Preview as client reads the same frozen branding a customer's own link would show -- the draft's or
// published version's own logo, not the organization's current one -- through the same quotes.view gate
// quote_customer_preview already enforces. The database function does the permission check; this route
// only turns its answer into bytes.
export const GET: RequestHandler = async (event) => {
	await requireContractor(event);

	const { data: objectKey, error } = await event.locals.supabase.rpc(
		'quote_preview_logo_object_key',
		{
			target_quote_id: event.params.id
		}
	);
	if (error) throw httpError(403, 'You do not have access to this quote.');
	if (!objectKey) throw httpError(404, 'No logo on this quote.');

	return streamOrganizationLogo(objectKey, event.request.headers.get('if-none-match'));
};

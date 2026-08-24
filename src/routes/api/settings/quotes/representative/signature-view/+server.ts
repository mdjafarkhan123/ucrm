import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { databaseError, notFound } from '$lib/server/api/errors';
import { streamRepresentativeSignature } from '$lib/server/settings/quote-representative-signature';

// One permanent URL for the representative's signature image, same reasoning as the logo's own view route:
// a presigned link expires in five minutes and the Settings preview needs a plain `<img src>`.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'settings.quotes.manage');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase
		.from('organization_settings')
		.select('quote_representative_signature_object_key')
		.eq('organization_id', check.auth.organization.id)
		.maybeSingle();
	if (error) return databaseError();
	if (!data?.quote_representative_signature_object_key)
		return notFound('No signature has been added yet.');

	return streamRepresentativeSignature(
		data.quote_representative_signature_object_key,
		event.request.headers.get('if-none-match')
	);
};

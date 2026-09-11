import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { PRIVATE_READ_HEADERS, notFound } from '$lib/server/api/errors';
import { signatureReadError } from '$lib/server/signatures/errors';

// What was actually signed, frozen as it stood at that moment. `job_signature_document` is definer: it
// decides access for itself and strips the prices and total for a reader without jobs.view_price. The job
// in the URL has to be the job the signature belongs to, so one job's page can never read another's
// signed document.
export const GET: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.view');
	if ('response' in check) return check.response;

	const { data, error } = await event.locals.supabase.rpc('job_signature_document', {
		target_signature_id: event.params.signatureId
	});
	if (error) return signatureReadError(error);

	const document = data as unknown as { job_id: string } | null;
	if (!document || document.job_id !== event.params.id)
		return notFound('That signature could not be found.');

	return json(document, { headers: PRIVATE_READ_HEADERS });
};

import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, notFound } from '$lib/server/api/errors';
import { getObjectStream } from '$lib/server/storage/r2';

// The Done screen's "Download the rows to fix" button. Scoped to the caller's active org under RLS so it can
// only ever read its own import's file.
export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationPermission(event, 'invoices.create');
	if ('response' in access) return access.response;

	const { data: batch, error } = await event.locals.supabase
		.from('import_batches')
		.select('id, source_filename, error_file_object_key')
		.eq('id', event.params.batchId)
		.eq('organization_id', access.auth.organization.id)
		.eq('entity_type', 'opening_balance')
		.maybeSingle();
	if (error) return databaseError();
	if (!batch || !batch.error_file_object_key) {
		return notFound('There is no error file for that import.');
	}

	let stream: ReadableStream;
	try {
		({ body: stream } = await getObjectStream(batch.error_file_object_key));
	} catch {
		return notFound('We could not open that error file. Please try the import again.');
	}

	const baseName = batch.source_filename.replace(/\.csv$/i, '');
	const downloadName = `${baseName}-rows-to-fix.csv`;

	return new Response(stream, {
		status: 200,
		headers: {
			...NO_STORE_HEADERS,
			'content-type': 'text/csv; charset=utf-8',
			'content-disposition': `attachment; filename="${downloadName}"`
		}
	});
};

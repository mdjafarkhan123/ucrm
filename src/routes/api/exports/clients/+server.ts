import type { RequestHandler } from './$types';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '$lib/database.types';
import { requireOrganizationAdmin } from '$lib/server/access/permission';
import { databaseError } from '$lib/server/api/errors';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	buildClientExportArchive,
	clientExportFileName,
	fetchClientExportData
} from '$lib/server/exports/client-export';

// Onboarding & Data Portability, Part 2: download the whole client book as a structured package.
//
// The mirror of the import: an owner/admin action (the whole book is sensitive -- a bad export leaks every
// client at once), gated on customers.view + the owner/admin role. Records only, built in memory and streamed
// straight down as a zip, so there is no stored object and no expiring link.
//
// A light rate limit sits in front because building the package reads every client record; the counter stops
// a hammering loop without getting in the way of an ordinary "export my clients" click.
const EXPORT_LIMIT = { windowSeconds: 60, maxAttempts: 5 };

export const GET: RequestHandler = async (event) => {
	const access = await requireOrganizationAdmin(event, 'customers.view');
	if ('response' in access) return access.response;

	const organizationId = access.auth.organization.id;

	let limit;
	try {
		limit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `client-export:${organizationId}`,
			...EXPORT_LIMIT
		});
	} catch {
		return databaseError();
	}
	if (!limit.allowed) return rateLimitedResponse(limit.retryAfterSeconds);

	let archive: Uint8Array;
	try {
		const data = await fetchClientExportData(
			event.locals.supabase as SupabaseClient<Database>,
			organizationId
		);
		archive = buildClientExportArchive(data);
	} catch (error) {
		console.error('Could not build the client export.', error);
		return databaseError();
	}

	return new Response(archive as unknown as BodyInit, {
		headers: {
			'content-type': 'application/zip',
			'content-disposition': `attachment; filename="${clientExportFileName()}"`,
			'content-length': String(archive.byteLength),
			'cache-control': 'no-store'
		}
	});
};

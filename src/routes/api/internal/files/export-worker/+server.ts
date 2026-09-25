import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import { runOrganizationExportWorker } from '$lib/server/files/organization-export';

// Woken every five minutes by its own cron (files-export-worker-wake-five-minutes,
// 20260925140000_files_media_organization_export.sql) rather than the one-minute upload-processing wake --
// see organization-export.ts for why a build needs a much longer timeout than that cron allows. Reuses the
// same bearer secret as that route; only the Vault URL entry differs.
function authorized(request: Request) {
	const token = request.headers.get('authorization')?.match(/^Bearer (.+)$/i)?.[1];
	const expected = getServerEnv().FILES_PROCESSING_WORKER_SECRET;
	if (!token || !expected) return false;
	const provided = Buffer.from(token);
	const wanted = Buffer.from(expected);
	return provided.length === wanted.length && timingSafeEqual(provided, wanted);
}

export const POST: RequestHandler = async ({ request }) => {
	if (!authorized(request))
		return json(
			{ error: 'Unauthorized.' },
			{ status: 401, headers: { 'cache-control': 'no-store' } }
		);

	// One job per invocation, deliberately: an export build is the heavy, rare exception in this pipeline
	// (see organization-export.ts), so this route never loops the way the small-batch file-processing wake
	// does. A second queued export simply waits for the next five-minute tick.
	const result = await runOrganizationExportWorker();

	return json(result, { headers: { 'cache-control': 'no-store' } });
};

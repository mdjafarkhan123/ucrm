import { timingSafeEqual } from 'node:crypto';
import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { getServerEnv } from '$lib/server/env';
import {
	runFileProcessingWorker,
	sweepAbandonedFileUploads,
	sweepExpiredTrash
} from '$lib/server/files/processing-worker';
import { sweepExpiredOrganizationExports } from '$lib/server/files/organization-export';
import {
	runProtectedDocumentChecks,
	sweepProtectedDocuments
} from '$lib/server/setup/protected-documents-worker';

// A burst of uploads can leave more than one batch waiting; loop until a claim comes back empty so it
// drains in one tick instead of ten. Bounded because each file is a whole object read and scan, and this
// runs on the container that is also serving the app.
const MAX_BATCHES_PER_INVOCATION = 10;

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

	let batches = 0;
	let claimed = 0;
	let available = 0;
	let failed = 0;
	let quarantined = 0;
	let deferred = 0;
	let thumbnails = 0;

	while (batches < MAX_BATCHES_PER_INVOCATION) {
		const result = await runFileProcessingWorker();
		batches += 1;
		claimed += result.claimed;
		available += result.available;
		failed += result.failed;
		quarantined += result.quarantined;
		deferred += result.deferred;
		thumbnails += result.thumbnails;
		if (result.claimed === 0) break;
		// Everything in that batch was handed back -- the scanner is down or storage is not answering.
		// Claiming the same rows again in a tight loop would just burn the invocation.
		if (result.deferred === result.claimed) break;
	}

	// Client onboarding B9a: protected setup documents. Few, and checked one batch a tick.
	const protectedChecks = await runProtectedDocumentChecks();

	// Cheap when there is nothing to collect: one indexed delete/update that usually matches no rows.
	const sweep = await sweepAbandonedFileUploads();
	const trashSweep = await sweepExpiredTrash();
	const exportSweep = await sweepExpiredOrganizationExports();
	const protectedSweep = await sweepProtectedDocuments();

	return json(
		{
			batches,
			claimed,
			available,
			failed,
			quarantined,
			deferred,
			thumbnails,
			abandoned: sweep.removed,
			purged: trashSweep.purged,
			exportsPurged: exportSweep.purged,
			protectedChecked: protectedChecks.claimed,
			protectedRefused: protectedChecks.refused,
			protectedDeleted: protectedSweep.deleted
		},
		{ headers: { 'cache-control': 'no-store' } }
	);
};

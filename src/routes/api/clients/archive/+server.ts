import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireClientPermission } from '$lib/server/access/clients';
import { NO_STORE_HEADERS, validationError } from '$lib/server/api/errors';
import { clientArchiveSchema, zodFieldErrors } from '$lib/server/validation/foundation.schema';

type ClientOpenWork = {
	requests: number;
	quotes: number;
	jobs: number;
	invoices: number;
};

type ArchiveOutcome = {
	client_id: string;
	applied: boolean;
	archived: boolean;
	open_work: ClientOpenWork | null;
};

// One door for archiving and restoring, whether the office picked one row or a selection. Each id goes
// through the same checked archive_client / restore_client the database owns, so a client still carrying
// live work is refused with its counts instead of failing the whole batch. Archiving something already
// archived is not an error, it is the same answer.
export const POST: RequestHandler = async (event) => {
	const access = await requireClientPermission(event, 'customers.archive');
	if ('response' in access) return access.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = clientArchiveSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { client_ids: clientIds, archived: wanted } = parsed.data;
	const command = wanted ? 'archive_client' : 'restore_client';

	// A selection this size is worth a handful of round trips, not one connection per row and not one held
	// after another. Ten at a time keeps the pool contribution bounded regardless of selection size.
	const CONCURRENCY = 10;
	const results: ArchiveOutcome[] = [];
	for (let start = 0; start < clientIds.length; start += CONCURRENCY) {
		const batch = clientIds.slice(start, start + CONCURRENCY);
		const answers = await Promise.all(
			batch.map((id) => event.locals.supabase.rpc(command, { target_client_id: id }))
		);
		answers.forEach(({ data, error }, index) => {
			const clientId = batch[index];
			if (error || !data) {
				results.push({ client_id: clientId, applied: false, archived: !wanted, open_work: null });
				return;
			}
			const answer = data as { applied: boolean; archived: boolean; open_work?: ClientOpenWork };
			results.push({
				client_id: clientId,
				applied: answer.applied,
				archived: answer.archived,
				open_work: answer.open_work ?? null
			});
		});
	}

	const changed = results.filter((result) => result.applied).length;
	return json(
		{ changed, skipped: results.length - changed, results },
		{ headers: NO_STORE_HEADERS }
	);
};

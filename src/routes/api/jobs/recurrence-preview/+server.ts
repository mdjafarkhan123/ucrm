import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import { NO_STORE_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { previewJobRecurrenceSchema } from '$lib/server/validation/jobs.schema';

// "26 visits, Sep 7 to Mar 1" — what the New Job form shows while someone is still choosing how often the
// work repeats. It reads no rows at all: the answer is arithmetic on dates the person has just typed, and it
// runs through `preview_job_recurrence`, which shares its date maths with the command that actually writes
// the visits. That sharing is the whole point — a preview promising 26 and a save writing 27 is the classic
// way this feature goes wrong.
//
// It is a POST because the rule is a nested object, not because it changes anything; nothing is written and
// the response is never stored.
export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'jobs.create');
	if ('response' in check) return check.response;

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = previewJobRecurrenceSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data, error } = await event.locals.supabase.rpc('preview_job_recurrence', {
		rule: parsed.data.recurrence
	});

	// The database refuses the same shapes the schema does, one step later; a rule it cannot read is a form
	// problem, not a failure of ours.
	if (error) {
		if (error.code === '23514' || error.code === '23502')
			return validationError({ form: error.message ?? 'That schedule cannot be read as entered.' });
		return databaseError();
	}

	return json(data, { headers: NO_STORE_HEADERS });
};

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import {
	NO_STORE_HEADERS,
	databaseError,
	notFound,
	unauthorized,
	validationError
} from '$lib/server/api/errors';
import { assessmentCompleteSchema, zodFieldErrors } from '$lib/server/validation/foundation.schema';

const NOT_FOUND = 'That request has no assessment to complete.';

// Ticking "Complete assessment" on the request. Jobber then leaves the request sitting at "Assessment
// complete" until someone converts or archives it — that prompt is the office's next move, not ours.
export const POST: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown = {};
	try {
		body = await event.request.json();
	} catch {
		// An empty body means "mark it complete", the only thing the checkbox sends most of the time.
	}

	const parsed = assessmentCompleteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = auth.organization.id;
	const supabase = event.locals.supabase;
	const requestId = event.params.id;

	const { data: assessment, error } = await supabase
		.from('assessments')
		.update({ completed_at: parsed.data.complete ? new Date().toISOString() : null })
		.eq('organization_id', organizationId)
		.eq('request_id', requestId)
		.select('id, starts_at, ends_at, all_day, instructions, completed_at')
		.maybeSingle();
	if (error) return databaseError();
	if (!assessment) return notFound(NOT_FOUND);

	// Completing moves the request to "Assessment complete". Reopening drops it back to the calendar
	// statuses, which are worked out from the start time on read — nothing to store for those. A request
	// already converted or archived keeps the status it has; the site visit no longer decides it.
	const { data: current, error: currentError } = await supabase
		.from('requests')
		.select('status')
		.eq('organization_id', organizationId)
		.eq('id', requestId)
		.maybeSingle();
	if (currentError) return databaseError();
	if (!current) return notFound(NOT_FOUND);

	let status = current.status;
	if (parsed.data.complete && (status === 'new' || status === 'unscheduled')) {
		status = 'assessment_completed';
	} else if (!parsed.data.complete && status === 'assessment_completed') {
		status = 'unscheduled';
	}

	if (status !== current.status) {
		const { error: statusError } = await supabase
			.from('requests')
			.update({ status })
			.eq('organization_id', organizationId)
			.eq('id', requestId);
		if (statusError) return databaseError();
	}

	return json(
		{ assessment, request: { id: requestId, stored_status: status } },
		{ headers: NO_STORE_HEADERS }
	);
};

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
import { assessmentWriteSchema, zodFieldErrors } from '$lib/server/validation/foundation.schema';

const NOT_FOUND = 'That request could not be found.';

// One route for the whole on-site assessment panel: turning it on, booking it, moving it, clearing the
// dates back to unscheduled, and changing who is going. The panel saves as a whole, so this replaces the
// assessment's fields and its assignee list in one go.
export const PUT: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = assessmentWriteSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = auth.organization.id;
	const supabase = event.locals.supabase;
	const requestId = event.params.id;
	const { assignee_ids: assigneeIds, ...fields } = parsed.data;

	const { data: existing, error: existingError } = await supabase
		.from('requests')
		.select('id, status, assessment:assessments(id, completed_at)')
		.eq('organization_id', organizationId)
		.eq('id', requestId)
		.maybeSingle();
	if (existingError) return databaseError();
	if (!existing) return notFound(NOT_FOUND);

	// The composite foreign key on assessment_assignees refuses a user from another organization, but the
	// office deserves a sentence rather than a database error.
	if (assigneeIds.length > 0) {
		const { data: members, error: membersError } = await supabase
			.from('organization_members')
			.select('user_id')
			.eq('organization_id', organizationId)
			.in('user_id', assigneeIds);
		if (membersError) return databaseError();
		if ((members ?? []).length !== new Set(assigneeIds).size) {
			return validationError({ assignee_ids: 'Assign people who are on your team.' });
		}
	}

	const { data: assessment, error: upsertError } = await supabase
		.from('assessments')
		.upsert(
			{ organization_id: organizationId, request_id: requestId, ...fields },
			{ onConflict: 'request_id' }
		)
		.select('id, starts_at, ends_at, all_day, instructions, completed_at')
		.single();
	if (upsertError) return databaseError();

	// Replace rather than merge: the panel always sends the full list of who is going.
	const { error: clearError } = await supabase
		.from('assessment_assignees')
		.delete()
		.eq('organization_id', organizationId)
		.eq('assessment_id', assessment.id);
	if (clearError) return databaseError();

	if (assigneeIds.length > 0) {
		const { error: assignError } = await supabase.from('assessment_assignees').insert(
			[...new Set(assigneeIds)].map((userId) => ({
				organization_id: organizationId,
				assessment_id: assessment.id,
				user_id: userId
			}))
		);
		if (assignError) return databaseError();
	}

	// Booking an assessment on a brand new request is what moves it out of "new". Once it is complete or
	// closed, the calendar no longer decides its status.
	let status = existing.status;
	if (status === 'new') {
		const { error: statusError } = await supabase
			.from('requests')
			.update({ status: 'unscheduled' })
			.eq('organization_id', organizationId)
			.eq('id', requestId);
		if (statusError) return databaseError();
		status = 'unscheduled';
	}

	return json(
		{
			assessment: { ...assessment, assignee_ids: assigneeIds },
			request: { id: requestId, stored_status: status }
		},
		{ headers: NO_STORE_HEADERS }
	);
};

// Removing the assessment altogether — Jobber's "this request does not need a site visit after all".
export const DELETE: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const organizationId = auth.organization.id;
	const supabase = event.locals.supabase;

	const { error } = await supabase
		.from('assessments')
		.delete()
		.eq('organization_id', organizationId)
		.eq('request_id', event.params.id);
	if (error) return databaseError();

	return json({ assessment: null }, { headers: NO_STORE_HEADERS });
};

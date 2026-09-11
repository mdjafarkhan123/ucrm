import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireAutomationAccess } from '$lib/server/access/automation';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { manualEnrollSchema } from '$lib/server/validation/automation-controls.schema';
import { commandErrorResponse, enrollmentDurationLimit } from '$lib/server/automation/commands';

// Contractor Settings Part 6D-5b: the Quote detail's record-level Automation surface. GET returns this quote's
// current and recent enrollment summaries (safe projection only) plus the active recipes a staff member may
// manually enroll it into; POST confirms a manual enroll. Access is decided here (view to read, control to
// write); the SECURITY DEFINER commands, run by service_role, re-check ownership and idempotency atomically.

const quoteIdSchema = z.string().uuid();

// Confirm the quote exists in the caller's organization before touching the engine. RLS on `quotes` already
// scopes the read to the tenant, so a foreign or unknown id simply comes back empty and we answer 404 without
// revealing whether it exists elsewhere.
async function quoteInOrg(event: Parameters<RequestHandler>[0], quoteId: string): Promise<boolean> {
	const { data } = await event.locals.supabase
		.from('quotes')
		.select('id')
		.eq('id', quoteId)
		.maybeSingle();
	return Boolean(data);
}

export const GET: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'view');
	if ('response' in check) return check.response;

	const quoteId = quoteIdSchema.safeParse(event.params.id);
	if (!quoteId.success) return json({ error: 'That quote does not exist.' }, { status: 404 });
	if (!(await quoteInOrg(event, quoteId.data)))
		return json({ error: 'That quote does not exist.' }, { status: 404 });

	const organizationId = check.auth.organization.id;
	const service = getOwnerSupabaseClient();

	// The enrollment summaries come from the safe per-record read; the enrollable recipes are the org's active
	// recipes (RLS-scoped through the viewer's client), which manual enroll previews one at a time.
	const [enrollmentsResult, recipesResult] = await Promise.all([
		service.rpc('automation_record_enrollments', {
			p_organization_id: organizationId,
			p_subject_type: 'quote',
			p_subject_id: quoteId.data,
			p_limit: 20
		}),
		event.locals.supabase
			.from('automation_recipes')
			.select('id, name')
			.eq('status', 'active')
			.not('current_version_id', 'is', null)
			.order('name', { ascending: true })
	]);

	if (enrollmentsResult.error) {
		console.error('Could not read record enrollments.', enrollmentsResult.error);
		return json({ error: 'Automation history could not be loaded.' }, { status: 500 });
	}
	if (recipesResult.error) {
		console.error('Could not read enrollable recipes.', recipesResult.error);
		return json({ error: 'Automation history could not be loaded.' }, { status: 500 });
	}

	return json(
		{
			can_control: check.automation.can_control_enrollment,
			enrollments: enrollmentsResult.data ?? [],
			enrollable_recipes: recipesResult.data ?? []
		},
		{ headers: NO_STORE_HEADERS }
	);
};

export const POST: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'control_enrollment');
	if ('response' in check) return check.response;

	const quoteId = quoteIdSchema.safeParse(event.params.id);
	if (!quoteId.success) return json({ error: 'That quote does not exist.' }, { status: 404 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = manualEnrollSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	if (!(await quoteInOrg(event, quoteId.data)))
		return json({ error: 'That quote does not exist.' }, { status: 404 });

	const service = getOwnerSupabaseClient();
	try {
		const { data, error } = await service.rpc('manual_enroll_automation', {
			p_organization_id: check.auth.organization.id,
			p_actor_user_id: check.auth.user.id,
			p_recipe_id: parsed.data.recipe_id,
			p_subject_type: 'quote',
			p_subject_id: quoteId.data,
			// null means "no expiry" (unlimited). The SQL param is nullable, but the generated RPC types
			// over-constrain it to a non-null number, so assert the resolved value through.
			p_max_enrollment_duration_days: enrollmentDurationLimit(check.automation) as number,
			p_idempotency_key: parsed.data.idempotency_key
		});
		if (error) throw error;
		return json(data, { headers: NO_STORE_HEADERS });
	} catch (error) {
		return commandErrorResponse(error, 'We could not enroll that quote. Please try again.');
	}
};

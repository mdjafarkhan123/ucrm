import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireAutomationAccess } from '$lib/server/access/automation';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { previewEnrollmentSchema } from '$lib/server/validation/automation-controls.schema';

// Contractor Settings Part 6D-5b: the read-only preview a staff member sees before confirming a manual enroll.
// It returns plain, tenant-safe facts (recipe version, first due time, expected message count, overlap) and
// never a definition or internal key. `control_enrollment` gates it because the preview only exists to lead
// into a write; confirm re-runs a fresh preview under an idempotency key.
export const POST: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'control_enrollment');
	if ('response' in check) return check.response;

	const quoteId = z.string().uuid().safeParse(event.params.id);
	if (!quoteId.success) return json({ error: 'That quote does not exist.' }, { status: 404 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = previewEnrollmentSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const { data: quote } = await event.locals.supabase
		.from('quotes')
		.select('id')
		.eq('id', quoteId.data)
		.maybeSingle();
	if (!quote) return json({ error: 'That quote does not exist.' }, { status: 404 });

	const service = getOwnerSupabaseClient();
	const { data, error } = await service.rpc('preview_automation_manual_enrollment', {
		p_organization_id: check.auth.organization.id,
		p_recipe_id: parsed.data.recipe_id,
		p_subject_type: 'quote',
		p_subject_id: quoteId.data
	});

	if (error) {
		console.error('Could not preview a manual enrollment.', error);
		return json({ error: 'That preview could not be loaded.' }, { status: 500 });
	}

	return json(data, { headers: NO_STORE_HEADERS });
};

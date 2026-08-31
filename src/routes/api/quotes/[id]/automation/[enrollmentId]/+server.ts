import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireAutomationAccess } from '$lib/server/access/automation';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { validationError, NO_STORE_HEADERS } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { controlEnrollmentSchema } from '$lib/server/validation/automation-controls.schema';
import { commandErrorResponse } from '$lib/server/automation/commands';

// Contractor Settings Part 6D-5b: the per-enrollment controls — pause, resume, skip next step, and stop — for
// one enrollment shown on the Quote detail. `control_enrollment` gates every action; the SECURITY DEFINER
// command re-checks organization ownership, enrollment state, and the idempotency key atomically, so a stale
// or foreign enrollment id fails inside the command rather than being trusted here.
export const POST: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'control_enrollment');
	if ('response' in check) return check.response;

	const enrollmentId = z.string().uuid().safeParse(event.params.enrollmentId);
	if (!enrollmentId.success)
		return json({ error: 'That enrollment does not exist.' }, { status: 404 });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return validationError({ form: 'Request body must be valid JSON.' });
	}

	const parsed = controlEnrollmentSchema.safeParse(body);
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const organizationId = check.auth.organization.id;
	const actorUserId = check.auth.user.id;
	const service = getOwnerSupabaseClient();

	try {
		let data: unknown;
		if (parsed.data.action === 'stop') {
			const result = await service.rpc('stop_automation_enrollment', {
				p_organization_id: organizationId,
				p_actor_user_id: actorUserId,
				p_enrollment_id: enrollmentId.data,
				// The command trims and `nullif`s this, so an empty string means "no reason" and it stamps
				// its own default — avoiding a nullable arg the generated RPC types reject.
				p_reason: parsed.data.reason ?? '',
				p_idempotency_key: parsed.data.idempotency_key
			});
			if (result.error) throw result.error;
			data = result.data;
		} else {
			const rpcName =
				parsed.data.action === 'pause'
					? 'pause_automation_enrollment'
					: parsed.data.action === 'resume'
						? 'resume_automation_enrollment'
						: 'skip_automation_enrollment_step';
			const result = await service.rpc(rpcName, {
				p_organization_id: organizationId,
				p_actor_user_id: actorUserId,
				p_enrollment_id: enrollmentId.data,
				p_idempotency_key: parsed.data.idempotency_key
			});
			if (result.error) throw result.error;
			data = result.data;
		}
		return json(data, { headers: NO_STORE_HEADERS });
	} catch (error) {
		return commandErrorResponse(error, 'That change could not be applied. Please try again.');
	}
};

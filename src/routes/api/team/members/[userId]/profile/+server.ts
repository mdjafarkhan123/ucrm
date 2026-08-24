import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { requireContractorTeamAdmin } from '$lib/server/access/contractor';
import {
	getTeamCommandClient,
	teamCommandErrorResponse,
	teamMemberProfileSummary
} from '$lib/server/access/team-commands';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	memberProfileSaveSchema,
	userIdSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

export const PATCH: RequestHandler = async (event) => {
	const required = await requireContractorTeamAdmin(event);
	if ('response' in required) return required.response;

	const parsedUserId = userIdSchema.safeParse(event.params.userId);
	if (!parsedUserId.success) {
		return json(
			{
				error: 'The employee identifier is invalid.',
				field_errors: zodAccessFieldErrors(parsedUserId.error)
			},
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json(
			{ error: 'Request body must be valid JSON.' },
			{ status: 400, headers: NO_STORE_HEADERS }
		);
	}
	const parsed = memberProfileSaveSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the member details.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const { auth } = required.context;
	const limit = await checkRateLimit(getTeamCommandClient(), {
		bucketKey: `team_member_profile:${auth.organization.id}:${auth.user.id}`,
		windowSeconds: 300,
		maxAttempts: 30
	});
	if (!limit.allowed) {
		const response = rateLimitedResponse(limit.retryAfterSeconds);
		response.headers.set('cache-control', 'no-store');
		return response;
	}

	const { data: member, error } = await getTeamCommandClient()
		.rpc('update_team_member_profile', {
			target_organization_id: auth.organization.id,
			actor_user_id: auth.user.id,
			target_user_id: parsedUserId.data,
			new_full_name: parsed.data.full_name,
			new_work_phone: parsed.data.work_phone,
			new_job_title: parsed.data.job_title,
			new_schedule_color: parsed.data.schedule_color,
			expected_profile_revision: parsed.data.expected_profile_revision
		})
		.single();
	if (error) {
		const response = teamCommandErrorResponse(error, 'Those member details could not be saved.');
		response.headers.set('cache-control', 'no-store');
		return response;
	}

	return json({ member: teamMemberProfileSummary(member) }, { headers: NO_STORE_HEADERS });
};

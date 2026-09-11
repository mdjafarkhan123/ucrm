import { json } from '@sveltejs/kit';
import type { RequestEvent, RequestHandler } from './$types';
import { NO_STORE_HEADERS, unauthorized } from '$lib/server/api/errors';
import { requireOrganization } from '$lib/server/auth/organization';
import {
	getTeamCommandClient,
	teamCommandErrorResponse,
	teamMemberAvailabilitySummary
} from '$lib/server/access/team-commands';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	memberAvailabilityExceptionDeleteSchema,
	memberAvailabilityExceptionSchema,
	userIdSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

// One dated exception at a time, rather than resending the whole list with every change: a person with a
// year of booked leave should not have to send two hundred rows to add one. The weekly pattern is the part
// that travels as a whole, because seven days only mean anything together.
//
// Authority is the same as the weekly pattern's -- yourself, or anybody if you are an owner or
// administrator -- and the database is the one enforcing it. See the sibling +server.ts for why this route
// does not use requireContractorTeamAdmin.

type Guarded =
	{ response: Response } | { organizationId: string; actorUserId: string; targetUserId: string };

async function guard(event: RequestEvent): Promise<Guarded> {
	const auth = await requireOrganization(event);
	if (!auth) return { response: unauthorized() };

	const parsedUserId = userIdSchema.safeParse(event.params.userId);
	if (!parsedUserId.success) {
		return {
			response: json(
				{ error: 'The employee identifier is invalid.' },
				{ status: 422, headers: NO_STORE_HEADERS }
			)
		};
	}

	const editingSelf = parsedUserId.data === auth.user.id;
	const isTeamManager = auth.organization.role === 'owner' || auth.organization.role === 'admin';
	if (!editingSelf && !isTeamManager) {
		return {
			response: json(
				{ error: "Only an owner or administrator can change someone else's availability." },
				{ status: 403, headers: NO_STORE_HEADERS }
			)
		};
	}

	const limit = await checkRateLimit(getTeamCommandClient(), {
		bucketKey: `member_availability:${auth.organization.id}:${auth.user.id}`,
		windowSeconds: 300,
		maxAttempts: 30
	});
	if (!limit.allowed) {
		const response = rateLimitedResponse(limit.retryAfterSeconds);
		response.headers.set('cache-control', 'no-store');
		return { response };
	}

	return {
		organizationId: auth.organization.id,
		actorUserId: auth.user.id,
		targetUserId: parsedUserId.data
	};
}

type ReadBody = { response: Response } | { body: unknown };

async function readJson(request: Request): Promise<ReadBody> {
	try {
		return { body: await request.json() };
	} catch {
		return {
			response: json(
				{ error: 'Request body must be valid JSON.' },
				{ status: 400, headers: NO_STORE_HEADERS }
			)
		};
	}
}

export const POST: RequestHandler = async (event) => {
	const guarded = await guard(event);
	if ('response' in guarded) return guarded.response;

	const read = await readJson(event.request);
	if ('response' in read) return read.response;

	const parsed = memberAvailabilityExceptionSchema.safeParse(read.body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review this date.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const { data: member, error } = await getTeamCommandClient()
		.rpc('save_member_availability_exception', {
			target_organization_id: guarded.organizationId,
			actor_user_id: guarded.actorUserId,
			target_user_id: guarded.targetUserId,
			target_date: parsed.data.exception_date,
			new_is_working: parsed.data.is_working,
			// The generated Args type marks these non-null because the generator cannot see that a `time`
			// parameter accepts NULL. A day off genuinely has no hours, so null is the right value to send.
			new_starts_at: parsed.data.starts_at as unknown as string,
			new_ends_at: parsed.data.ends_at as unknown as string,
			new_reason: parsed.data.reason,
			expected_availability_revision: parsed.data.expected_availability_revision
		})
		.single();
	if (error) {
		const response = teamCommandErrorResponse(error, 'That date could not be saved.');
		response.headers.set('cache-control', 'no-store');
		return response;
	}

	return json({ member: teamMemberAvailabilitySummary(member) }, { headers: NO_STORE_HEADERS });
};

export const DELETE: RequestHandler = async (event) => {
	const guarded = await guard(event);
	if ('response' in guarded) return guarded.response;

	const read = await readJson(event.request);
	if ('response' in read) return read.response;

	const parsed = memberAvailabilityExceptionDeleteSchema.safeParse(read.body);
	if (!parsed.success) {
		return json(
			{
				error: 'That date could not be removed.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const { data: member, error } = await getTeamCommandClient()
		.rpc('delete_member_availability_exception', {
			target_organization_id: guarded.organizationId,
			actor_user_id: guarded.actorUserId,
			target_user_id: guarded.targetUserId,
			target_exception_id: parsed.data.exception_id,
			expected_availability_revision: parsed.data.expected_availability_revision
		})
		.single();
	if (error) {
		const response = teamCommandErrorResponse(error, 'That date could not be removed.');
		response.headers.set('cache-control', 'no-store');
		return response;
	}

	return json({ member: teamMemberAvailabilitySummary(member) }, { headers: NO_STORE_HEADERS });
};

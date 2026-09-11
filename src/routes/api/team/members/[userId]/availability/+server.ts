import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import {
	NO_STORE_HEADERS,
	PRIVATE_READ_HEADERS,
	databaseError,
	unauthorized
} from '$lib/server/api/errors';
import { requireOrganization } from '$lib/server/auth/organization';
import {
	getTeamCommandClient,
	teamCommandErrorResponse,
	teamMemberAvailabilitySummary
} from '$lib/server/access/team-commands';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import {
	memberWeeklyAvailabilitySchema,
	userIdSchema,
	zodAccessFieldErrors
} from '$lib/server/validation/access.schema';

// Upcoming dated exceptions only. A day off that has already passed is history nobody edits, and leaving it
// out keeps a member with years of service from carrying years of leave into every page load. The cap is a
// guard against a runaway list, not a page size.
const MAX_UPCOMING_EXCEPTIONS = 200;

// One person's availability, for their own Availability section.
//
// Any teammate may read it -- the same rule as the calendar's read, and the same RLS policy behind it. Who
// may *change* it is a narrower question, answered by PATCH below and by the database.
export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const parsedUserId = userIdSchema.safeParse(event.params.userId);
	if (!parsedUserId.success) {
		return json({ error: 'The employee identifier is invalid.' }, { status: 422 });
	}

	const supabase = event.locals.supabase;
	const today = new Date().toISOString().slice(0, 10);

	const [memberResult, patternResult, exceptionResult] = await Promise.all([
		supabase
			.from('organization_members')
			.select('availability_revision')
			.eq('organization_id', auth.organization.id)
			.eq('user_id', parsedUserId.data)
			.maybeSingle(),
		supabase
			.from('organization_member_availability')
			.select('weekday, is_working, starts_at, ends_at')
			.eq('organization_id', auth.organization.id)
			.eq('user_id', parsedUserId.data)
			.order('weekday'),
		supabase
			.from('organization_member_availability_exceptions')
			.select('id, exception_date, is_working, starts_at, ends_at, reason')
			.eq('organization_id', auth.organization.id)
			.eq('user_id', parsedUserId.data)
			.gte('exception_date', today)
			.order('exception_date')
			.limit(MAX_UPCOMING_EXCEPTIONS)
	]);

	if (memberResult.error || patternResult.error || exceptionResult.error) return databaseError();
	if (!memberResult.data) {
		return json({ error: 'That team member was not found.' }, { status: 404 });
	}

	const editingSelf = parsedUserId.data === auth.user.id;
	const isTeamManager = auth.organization.role === 'owner' || auth.organization.role === 'admin';

	return json(
		{
			availability_revision: memberResult.data.availability_revision,
			can_edit: editingSelf || isTeamManager,
			pattern: patternResult.data ?? [],
			exceptions: exceptionResult.data ?? []
		},
		{ headers: PRIVATE_READ_HEADERS }
	);
};

// Saving one person's ordinary working week.
//
// This route deliberately does not use requireContractorTeamAdmin, the way every other team member route
// does. Availability is the one section of a member's record they own themselves -- "Owners and
// administrators manage any member's availability, and members may update their own" -- so a field member
// with no team.manage permission has to get through the door to edit their own row. The real authority is
// private.authorize_member_availability_command in the database, which knows the "self, or an owner or
// administrator" rule. The check below is the same rule stated early, so somebody editing a colleague they
// have no business editing gets an honest 403 instead of a conflict code.
export const PATCH: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const parsedUserId = userIdSchema.safeParse(event.params.userId);
	if (!parsedUserId.success) {
		return json(
			{ error: 'The employee identifier is invalid.' },
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const editingSelf = parsedUserId.data === auth.user.id;
	const isTeamManager = auth.organization.role === 'owner' || auth.organization.role === 'admin';
	if (!editingSelf && !isTeamManager) {
		return json(
			{ error: "Only an owner or administrator can change someone else's availability." },
			{ status: 403, headers: NO_STORE_HEADERS }
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

	const parsed = memberWeeklyAvailabilitySchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review this working week.',
				field_errors: zodAccessFieldErrors(parsed.error)
			},
			{ status: 422, headers: NO_STORE_HEADERS }
		);
	}

	const limit = await checkRateLimit(getTeamCommandClient(), {
		bucketKey: `member_availability:${auth.organization.id}:${auth.user.id}`,
		windowSeconds: 300,
		maxAttempts: 30
	});
	if (!limit.allowed) {
		const response = rateLimitedResponse(limit.retryAfterSeconds);
		response.headers.set('cache-control', 'no-store');
		return response;
	}

	const { data: member, error } = await getTeamCommandClient()
		.rpc('save_member_weekly_availability', {
			target_organization_id: auth.organization.id,
			actor_user_id: auth.user.id,
			target_user_id: parsedUserId.data,
			new_pattern: parsed.data.pattern,
			expected_availability_revision: parsed.data.expected_availability_revision
		})
		.single();
	if (error) {
		const response = teamCommandErrorResponse(error, 'That working week could not be saved.');
		response.headers.set('cache-control', 'no-store');
		return response;
	}

	return json({ member: teamMemberAvailabilitySummary(member) }, { headers: NO_STORE_HEADERS });
};

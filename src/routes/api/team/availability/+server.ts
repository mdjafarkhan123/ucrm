import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganization } from '$lib/server/auth/organization';
import { PRIVATE_READ_HEADERS, databaseError, unauthorized } from '$lib/server/api/errors';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { scheduleWindowQuerySchema } from '$lib/server/validation/schedule.schema';

// When the team can work, for the window the calendar is showing.
//
// Two small reads rather than one join: the weekly pattern is at most seven rows per member and does not
// depend on the window at all, while exceptions are dated and do. Joining them would repeat each person's
// whole week once per exception for no gain.
//
// Any member may read this. The Schedule warns a dispatcher that the person they are about to assign is not
// working, and a dispatcher is often an office or sales member with no team.manage permission. RLS says the
// same thing: both policies are private.is_organization_member, so this route cannot reach past the caller's
// own organization even if the filter below were wrong.
//
// A team fits on one screen, so the pattern read is not paginated. The cap is a guard against a runaway
// organization, not a page size -- 200 members is 1,400 rows, the same ceiling /api/team/assignable uses.
const MAX_PATTERN_ROWS = 1_400;

export const GET: RequestHandler = async (event) => {
	const auth = await requireOrganization(event);
	if (!auth) return unauthorized();

	const parsed = scheduleWindowQuerySchema.safeParse({
		from: event.url.searchParams.get('from') ?? '',
		to: event.url.searchParams.get('to') ?? ''
	});
	if (!parsed.success) {
		return json(
			{ error: 'That date window is not valid.', field_errors: zodFieldErrors(parsed.error) },
			{ status: 422 }
		);
	}

	const supabase = event.locals.supabase;

	const [patternResult, exceptionResult] = await Promise.all([
		supabase
			.from('organization_member_availability')
			.select('user_id, weekday, is_working, starts_at, ends_at')
			.eq('organization_id', auth.organization.id)
			.limit(MAX_PATTERN_ROWS),
		supabase
			.from('organization_member_availability_exceptions')
			.select('user_id, exception_date, is_working, starts_at, ends_at')
			.eq('organization_id', auth.organization.id)
			.gte('exception_date', parsed.data.from)
			.lte('exception_date', parsed.data.to)
	]);

	if (patternResult.error || exceptionResult.error) return databaseError();

	// The reason a day is an exception is the member's own note. It belongs on the Availability screen, not
	// in the calendar's warning, so it is never sent here.
	return json(
		{ pattern: patternResult.data ?? [], exceptions: exceptionResult.data ?? [] },
		{ headers: PRIVATE_READ_HEADERS }
	);
};

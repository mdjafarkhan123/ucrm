import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { requireSupportMember } from '$lib/server/support/access';
import { readSupportMessages } from '$lib/server/support/read';
import { FORMER_MEMBER, countTeamThreads, teammateNames } from '$lib/server/support/team';
import { supportMemberThreadQuerySchema } from '$lib/server/validation/support.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import type { SupportThread } from '$lib/support/api';

// The signed-in member's own conversation with Uplift, or — with `thread_id` — another conversation in
// their organization that row level security lets them see (D3: one they were added to, or any one for an
// owner or admin). The explicit filters say the same as the policy so the reads use their indexes.
export const GET: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	const parsed = supportMemberThreadQuerySchema.safeParse({
		limit: event.url.searchParams.get('limit') ?? undefined,
		thread_id: event.url.searchParams.get('thread_id') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const supabase = event.locals.supabase;
	const organizationId = check.auth.organization.id;
	const userId = check.auth.user.id;
	const requested = parsed.data.thread_id;

	const threadRead = supabase
		.from('support_threads')
		.select('id, started_by_user_id')
		.eq('organization_id', organizationId);
	const [threadResult, settingsResult, teamCount] = await Promise.all([
		requested
			? threadRead.eq('id', requested).maybeSingle()
			: threadRead.eq('started_by_user_id', userId).maybeSingle(),
		supabase.from('platform_support_settings').select('availability_note').maybeSingle(),
		// The "Team chats" link sits on the member's own conversation only.
		requested ? Promise.resolve(0) : countTeamThreads(supabase, organizationId, userId)
	]);
	if (threadResult.error || settingsResult.error || teamCount === null) return databaseError();

	const row = threadResult.data;
	// Another member's conversation that is not visible reads exactly like one that does not exist.
	if (requested && !row)
		return json({ error: 'That conversation could not be found.' }, { status: 404 });

	let started_by_name: string | null = null;
	if (row && row.started_by_user_id !== userId) {
		try {
			const names = await teammateNames(
				supabase,
				row.started_by_user_id ? [row.started_by_user_id] : []
			);
			started_by_name =
				(row.started_by_user_id && names.get(row.started_by_user_id)) || FORMER_MEMBER;
		} catch {
			return databaseError();
		}
	}

	const base = {
		availability_note: settingsResult.data?.availability_note ?? '',
		started_by_name,
		team_thread_count: teamCount
	};
	if (!row) {
		const empty: SupportThread = { thread_id: null, messages: [], has_earlier: false, ...base };
		return json(empty, { headers: PRIVATE_READ_HEADERS });
	}

	const page = await readSupportMessages(supabase, row.id, parsed.data.limit);
	if (!page) return databaseError();

	const thread: SupportThread = { thread_id: row.id, ...page, ...base };
	return json(thread, { headers: PRIVATE_READ_HEADERS });
};

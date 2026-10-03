import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { requireSupportMember } from '$lib/server/support/access';
import { readSupportMessages } from '$lib/server/support/read';
import { FORMER_MEMBER, teammateNames } from '$lib/server/support/team';
import { supportMemberThreadQuerySchema } from '$lib/server/validation/support.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import { setupSectionLabel } from '$lib/setup/catalogue';
import type { SupportStatus, SupportThread, SupportTopic } from '$lib/support/api';

// One chat with Uplift that row level security lets the member see: their own, one they were added to, or
// any one in their organization for an owner or admin (D3). The organization filter says the same as the
// policy so the read uses its index.
export const GET: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	const parsed = supportMemberThreadQuerySchema.safeParse({
		limit: event.url.searchParams.get('limit') ?? undefined,
		thread_id: event.url.searchParams.get('thread_id') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const supabase = event.locals.supabase;
	const userId = check.auth.user.id;

	const [threadResult, settingsResult, page] = await Promise.all([
		supabase
			.from('support_threads')
			.select('id, topic, started_by_user_id, status, context_section')
			.eq('organization_id', check.auth.organization.id)
			.eq('id', parsed.data.thread_id)
			.maybeSingle(),
		supabase.from('platform_support_settings').select('availability_note').maybeSingle(),
		readSupportMessages(supabase, parsed.data.thread_id, parsed.data.limit)
	]);
	if (threadResult.error || settingsResult.error || !page) return databaseError();

	const row = threadResult.data;
	// A chat that is not visible reads exactly like one that does not exist.
	if (!row) return json({ error: 'That conversation could not be found.' }, { status: 404 });

	let started_by_name: string | null = null;
	if (row.started_by_user_id !== userId) {
		try {
			const names = await teammateNames(
				supabase,
				check.auth.organization.id,
				row.started_by_user_id ? [row.started_by_user_id] : []
			);
			started_by_name =
				(row.started_by_user_id && names.get(row.started_by_user_id)) || FORMER_MEMBER;
		} catch {
			return databaseError();
		}
	}

	const thread: SupportThread = {
		thread_id: row.id,
		topic: row.topic as SupportTopic,
		// The same rule as public.set_support_thread_topic, which decides for real.
		can_change_topic:
			row.started_by_user_id === userId ||
			check.auth.organization.role === 'owner' ||
			check.auth.organization.role === 'admin',
		...page,
		availability_note: settingsResult.data?.availability_note ?? '',
		started_by_name,
		status: row.status as SupportStatus,
		context_label: setupSectionLabel(row.context_section)
	};
	return json(thread, { headers: PRIVATE_READ_HEADERS });
};

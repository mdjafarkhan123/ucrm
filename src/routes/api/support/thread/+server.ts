import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { PRIVATE_READ_HEADERS, databaseError, validationError } from '$lib/server/api/errors';
import { requireSupportMember } from '$lib/server/support/access';
import { readSupportMessages } from '$lib/server/support/read';
import { supportThreadQuerySchema } from '$lib/server/validation/support.schema';
import { zodFieldErrors } from '$lib/server/validation/foundation.schema';
import type { SupportThread } from '$lib/support/api';

// The signed-in member's own conversation with Uplift. Row level security is what keeps it to their own
// thread; the explicit filter below says the same thing so the read uses the per-member index.
export const GET: RequestHandler = async (event) => {
	const check = await requireSupportMember(event);
	if ('response' in check) return check.response;

	const parsed = supportThreadQuerySchema.safeParse({
		limit: event.url.searchParams.get('limit') ?? undefined
	});
	if (!parsed.success) return validationError(zodFieldErrors(parsed.error));

	const supabase = event.locals.supabase;
	const [threadResult, settingsResult] = await Promise.all([
		supabase
			.from('support_threads')
			.select('id')
			.eq('organization_id', check.auth.organization.id)
			.eq('started_by_user_id', check.auth.user.id)
			.maybeSingle(),
		supabase.from('platform_support_settings').select('availability_note').maybeSingle()
	]);
	if (threadResult.error || settingsResult.error) return databaseError();

	const availability_note = settingsResult.data?.availability_note ?? '';
	const threadId = threadResult.data?.id ?? null;
	if (!threadId) {
		const empty: SupportThread = {
			thread_id: null,
			messages: [],
			has_earlier: false,
			availability_note
		};
		return json(empty, { headers: PRIVATE_READ_HEADERS });
	}

	const page = await readSupportMessages(supabase, threadId, parsed.data.limit);
	if (!page) return databaseError();

	const thread: SupportThread = { thread_id: threadId, ...page, availability_note };
	return json(thread, { headers: PRIVATE_READ_HEADERS });
};

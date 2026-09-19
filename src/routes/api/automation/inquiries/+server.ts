import { json } from '@sveltejs/kit';
import { z } from 'zod';
import type { RequestHandler } from './$types';
import { requireAutomationAccess, type AutomationAccessCheck } from '$lib/server/access/automation';
import type { Database } from '$lib/database.types';
import { getOwnerSupabaseClient } from '$lib/server/db/owner-supabase';
import { NO_STORE_HEADERS } from '$lib/server/api/errors';
import { hasPermission } from '$lib/server/access/permission';

// CRM launch readiness Part 4 Stage 6: a website inquiry's follow-up history, read from the record it became — a
// Request (through its form submission) or a chat session. Exactly one of `request_id` / `chat_session_id`. The
// record is first read through the viewer's own RLS client, so a record they cannot see answers 404 without
// revealing whether it exists; the enrollment summaries then come from the service-role safe projection.
const querySchema = z.union([
	z.object({ request_id: z.string().uuid(), chat_session_id: z.undefined() }),
	z.object({ request_id: z.undefined(), chat_session_id: z.string().uuid() })
]);

export const GET: RequestHandler = async (event) => {
	const check = await requireAutomationAccess(event, 'view');
	if ('response' in check) return check.response;

	const parsed = querySchema.safeParse({
		request_id: event.url.searchParams.get('request_id') ?? undefined,
		chat_session_id: event.url.searchParams.get('chat_session_id') ?? undefined
	});
	if (!parsed.success) return json({ error: 'That record does not exist.' }, { status: 404 });

	const { request_id: requestId, chat_session_id: chatSessionId } = parsed.data;
	const organizationId = check.auth.organization.id;
	const notFound = () => json({ error: 'That record does not exist.' }, { status: 404 });
	if (requestId) {
		const visible = await event.locals.supabase
			.from('requests')
			.select('id')
			.eq('id', requestId)
			.maybeSingle();
		if (visible.error || !visible.data) return notFound();
	} else if (!(await canSeeChatSession(check, chatSessionId!))) {
		return notFound();
	}

	const { data, error } = await getOwnerSupabaseClient().rpc('automation_inquiry_enrollments', {
		p_organization_id: organizationId,
		p_request_id: requestId ?? null,
		p_chat_session_id: chatSessionId ?? null,
		p_limit: 20
		// p_request_id/p_chat_session_id are genuinely one-or-the-other-null (querySchema above enforces
		// exactly one); cast because the generated Args type can't express a nullable scalar without a SQL
		// default (see the matching comment in stripe-checkout-events.ts).
	} as Database['public']['Functions']['automation_inquiry_enrollments']['Args']);
	if (error) {
		console.error('Could not read inquiry enrollments.', error);
		return json({ error: 'Automation history could not be loaded.' }, { status: 500 });
	}

	return json(
		{ can_control: check.automation.can_control_enrollment, enrollments: data ?? [] },
		{ headers: NO_STORE_HEADERS }
	);
};

// Chat sessions have no staff RLS policy; the inbox reads them with the service role behind conversation
// permissions (`/api/communications/email-history`). Mirror that rule: Team Inbox viewers see any session in
// their organization, assigned-only viewers only a session whose client is assigned to or followed by them.
async function canSeeChatSession(
	check: Exclude<AutomationAccessCheck, { response: Response }>,
	chatSessionId: string
) {
	const organizationId = check.auth.organization.id;
	const canViewTeam = hasPermission(check.access, 'conversations.view_team');
	if (!canViewTeam && !hasPermission(check.access, 'conversations.view_assigned')) return false;

	const owner = getOwnerSupabaseClient();
	const session = await owner
		.from('website_chat_sessions')
		.select('client_id')
		.eq('organization_id', organizationId)
		.eq('id', chatSessionId)
		.maybeSingle();
	if (session.error || !session.data) return false;
	if (canViewTeam) return true;
	if (!session.data.client_id) return false;

	const [assigned, followed] = await Promise.all([
		owner
			.from('communication_conversation_assignments')
			.select('client_id')
			.eq('organization_id', organizationId)
			.eq('client_id', session.data.client_id)
			.eq('assigned_to', check.auth.user.id)
			.limit(1),
		owner
			.from('communication_conversation_followers')
			.select('client_id')
			.eq('organization_id', organizationId)
			.eq('client_id', session.data.client_id)
			.eq('user_id', check.auth.user.id)
			.limit(1)
	]);
	return Boolean(assigned.data?.length || followed.data?.length);
}

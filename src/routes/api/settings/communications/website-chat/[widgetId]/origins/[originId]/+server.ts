import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	WebsiteChatWidgetCommandError,
	removeWebsiteChatWidgetOrigin
} from '$lib/server/communications/website-chat-widget-commands';
import { organizationIdSchema } from '$lib/server/validation/access.schema';

const noStore = { 'Cache-Control': 'no-store' };

export const DELETE: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const widgetId = organizationIdSchema.safeParse(event.params.widgetId);
	const originId = organizationIdSchema.safeParse(event.params.originId);
	if (!widgetId.success || !originId.success)
		return json({ error: 'The domain could not be found.' }, { status: 422, headers: noStore });

	try {
		await removeWebsiteChatWidgetOrigin(
			event.locals.supabase,
			check.auth.organization.id,
			widgetId.data,
			originId.data
		);
		return json({ status: 'deleted' }, { headers: noStore });
	} catch (error) {
		if (error instanceof WebsiteChatWidgetCommandError) {
			return json(
				{ error: error.message, reason: error.reason },
				{ status: error.status, headers: noStore }
			);
		}
		console.error('Could not remove the Website Chat widget domain.', error);
		return json({ error: 'The domain could not be removed.' }, { status: 500, headers: noStore });
	}
};

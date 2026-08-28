import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	WebsiteChatWidgetCommandError,
	addWebsiteChatWidgetOrigin
} from '$lib/server/communications/website-chat-widget-commands';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationFieldErrors,
	websiteChatWidgetOriginCreateSchema
} from '$lib/server/validation/communications.schema';

const noStore = { 'Cache-Control': 'no-store' };

export const POST: RequestHandler = async (event) => {
	const check = await requireOrganizationPermission(event, 'conversations.manage_connections');
	if ('response' in check) return check.response;

	const widgetId = organizationIdSchema.safeParse(event.params.widgetId);
	if (!widgetId.success)
		return json({ error: 'The widget identifier is invalid.' }, { status: 422, headers: noStore });

	let body: unknown;
	try {
		body = await event.request.json();
	} catch {
		return json({ error: 'Request body must be valid JSON.' }, { status: 400, headers: noStore });
	}
	const parsed = websiteChatWidgetOriginCreateSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the domain.',
				field_errors: communicationFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	try {
		const rateLimit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `website_chat_widget_origin:${check.auth.organization.id}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 40
		});
		if (!rateLimit.allowed) {
			const response = rateLimitedResponse(rateLimit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const origin = await addWebsiteChatWidgetOrigin(
			event.locals.supabase,
			check.auth.organization.id,
			widgetId.data,
			parsed.data.origin
		);
		return json({ origin }, { status: 201, headers: noStore });
	} catch (error) {
		if (error instanceof WebsiteChatWidgetCommandError) {
			return json(
				{ error: error.message, reason: error.reason },
				{ status: error.status, headers: noStore }
			);
		}
		console.error('Could not add the Website Chat widget domain.', error);
		return json({ error: 'The domain could not be added.' }, { status: 500, headers: noStore });
	}
};

import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { requireOrganizationPermission } from '$lib/server/access/permission';
import {
	WebsiteChatWidgetCommandError,
	updateWebsiteChatWidget
} from '$lib/server/communications/website-chat-widget-commands';
import { checkRateLimit, rateLimitedResponse } from '$lib/server/security/rate-limit';
import { organizationIdSchema } from '$lib/server/validation/access.schema';
import {
	communicationFieldErrors,
	websiteChatWidgetUpdateSchema
} from '$lib/server/validation/communications.schema';

const noStore = { 'Cache-Control': 'no-store' };

export const PATCH: RequestHandler = async (event) => {
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
	const parsed = websiteChatWidgetUpdateSchema.safeParse(body);
	if (!parsed.success) {
		return json(
			{
				error: 'Please review the widget details.',
				field_errors: communicationFieldErrors(parsed.error)
			},
			{ status: 422, headers: noStore }
		);
	}

	try {
		const rateLimit = await checkRateLimit(event.locals.supabase, {
			bucketKey: `website_chat_widget:${check.auth.organization.id}:${check.auth.user.id}`,
			windowSeconds: 300,
			maxAttempts: 20
		});
		if (!rateLimit.allowed) {
			const response = rateLimitedResponse(rateLimit.retryAfterSeconds);
			response.headers.set('Cache-Control', 'no-store');
			return response;
		}

		const input = parsed.data;
		const widget = await updateWebsiteChatWidget(
			event.locals.supabase,
			check.auth.organization.id,
			widgetId.data,
			{
				name: input.name,
				launcherPosition: input.launcher_position,
				teaserText: input.teaser_text,
				greetingText: input.greeting_text,
				contactRequirement: input.contact_requirement,
				availabilityVisibilityMode: input.availability_visibility_mode,
				sourceLabel: input.source_label,
				privacyPolicyUrl: input.privacy_policy_url,
				channelOptions: input.channel_options,
				expectedRevision: input.expected_revision,
				published: input.published,
				disabled: input.disabled
			}
		);
		return json({ widget }, { headers: noStore });
	} catch (error) {
		if (error instanceof WebsiteChatWidgetCommandError) {
			return json(
				{ error: error.message, reason: error.reason },
				{ status: error.status, headers: noStore }
			);
		}
		console.error('Could not update the Website Chat widget.', error);
		return json(
			{ error: 'The Website Chat widget could not be changed.' },
			{ status: 500, headers: noStore }
		);
	}
};
